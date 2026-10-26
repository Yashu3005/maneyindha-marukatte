const crypto = require('crypto');
const Order = require('../models/Order');
const Transaction = require('../models/Transaction');
const PaymentEvent = require('../models/PaymentEvent');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');
const { getRazorpay } = require('../config/razorpay');

const CURRENCY = 'INR';
const MIN_PAISE = 100; // Razorpay's minimum is ₹1

const hmacHex = (secret, message) => crypto.createHmac('sha256', secret).update(message).digest('hex');
const isHex = (s, len) => typeof s === 'string' && s.length === len && /^[0-9a-f]+$/i.test(s);
function safeEqualHex(a, b) {
  if (!isHex(a, 64) || !isHex(b, 64)) return false;
  return crypto.timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}
// Rupees (as stored) -> integer paise. Math.round guards against float artefacts (e.g. 549.1*100).
const toPaise = (rupees) => Math.round(Number(rupees) * 100);

// Razorpay SDK errors look like { statusCode, error: { code, description } }.
function providerError(e, what) {
  logger.error(`Razorpay ${what} failed: ${e?.statusCode || ''} ${e?.error?.code || e?.message || 'unknown'}`);
  return new AppError('Payment provider error. Please try again.', 502, 'PAYMENT_PROVIDER_ERROR');
}

async function ownOrder(userId, orderId) {
  const order = await Order.findOne({ _id: orderId, customer: userId });
  if (!order) throw new AppError('Order not found', 404); // other people's orders look identical to missing ones
  return order;
}

function checkoutParams(order, user) {
  return {
    keyId: process.env.RAZORPAY_KEY_ID, // public identifier; the secret never leaves the server
    razorpayOrderId: order.payment.razorpayOrderId,
    amount: order.payment.amountPaise,
    currency: CURRENCY,
    orderId: String(order._id),
    orderNumber: order.orderNumber,
    prefill: { name: user?.name, email: user?.email, contact: user?.phone },
  };
}

/**
 * Creates (or returns the existing) Razorpay order for one of the caller's own orders.
 * The amount is computed here from the stored order — the client never supplies it.
 */
exports.createRazorpayOrder = async (user, orderId) => {
  const order = await ownOrder(user.id, orderId);
  if (order.payment?.method !== 'razorpay') throw new AppError('This order is not an online-payment order', 422);
  if (order.status !== 'pending') throw new AppError(`Order is ${order.status} and can no longer be paid`, 422);
  if (order.payment.status === 'paid') throw new AppError('Order is already paid', 409);

  // Idempotent: the same Razorpay order is reused for retries, so duplicate orders cannot be created.
  if (order.payment.razorpayOrderId) return checkoutParams(order, user.profile);

  const amount = toPaise(order.amounts.total);
  if (!Number.isInteger(amount) || amount < MIN_PAISE) throw new AppError('Order total is too low for online payment', 422);

  let rzpOrder;
  try {
    rzpOrder = await getRazorpay().orders.create({
      amount, currency: CURRENCY, receipt: order.orderNumber, notes: { orderId: String(order._id) },
    });
  } catch (e) {
    if (e instanceof AppError) throw e;
    throw providerError(e, 'order creation');
  }
  if (!rzpOrder?.id || rzpOrder.amount !== amount) throw new AppError('Payment provider returned an unexpected order', 502, 'PAYMENT_PROVIDER_ERROR');

  // Compare-and-set: if two requests raced, only the first Razorpay order id is kept.
  const res = await Order.updateOne(
    { _id: order._id, 'payment.razorpayOrderId': null },
    { $set: { 'payment.razorpayOrderId': rzpOrder.id, 'payment.amountPaise': amount } }
  );
  const fresh = res.modifiedCount === 1 ? await Order.findOne({ _id: order._id }) : await Order.findOne({ _id: order._id });
  return checkoutParams(fresh, user.profile);
};

// Flip to paid exactly once (compare-and-set on payment.status) and write the ledger entry.
async function markPaid(order, paymentId, extra = {}) {
  const updated = await Order.findOneAndUpdate(
    { _id: order._id, 'payment.status': { $ne: 'paid' } },
    {
      $set: {
        'payment.status': 'paid', 'payment.razorpayPaymentId': paymentId, 'payment.paidAt': new Date(),
        'payment.failureReason': null,
        ...(['cancelled', 'rejected', 'payment_failed'].includes(order.status) ? { 'payment.needsRefund': true } : {}),
        ...extra,
      },
    },
    { new: true }
  );
  if (!updated) {
    // Already paid. A *different* payment id for an already-paid order is a double payment: flag for refund.
    const current = await Order.findOne({ _id: order._id });
    if (current?.payment?.razorpayPaymentId && current.payment.razorpayPaymentId !== paymentId) {
      logger.warn(`Duplicate payment ${paymentId} for already-paid order ${order._id}; manual refund needed`);
    }
    return { order: current, changed: false };
  }
  await Transaction.create({
    user: order.customer, order: order._id, type: 'payment', amount: order.amounts.total, currency: CURRENCY,
    gateway: 'razorpay', gatewayRef: paymentId, status: 'success',
  });
  if (updated.payment.needsRefund) logger.warn(`Order ${order._id} was paid after being ${order.status}; manual refund needed`);
  return { order: updated, changed: true };
}

async function markFailed(order, reason) {
  // Never downgrade a paid order; a failed attempt leaves the order pending so the customer can retry.
  await Order.updateOne(
    { _id: order._id, 'payment.status': { $ne: 'paid' } },
    { $set: { 'payment.status': 'failed', 'payment.failureReason': String(reason || 'payment failed').slice(0, 200) } }
  );
}

const view = (order) => ({
  orderId: String(order._id), orderStatus: order.status,
  paymentStatus: order.payment?.status, paymentMethod: order.payment?.method,
});

/**
 * Called after the browser's Checkout success callback. The callback is NOT trusted: we verify the
 * signature (HMAC-SHA256 of "<our order_id>|<payment_id>" with the key secret) and then confirm the
 * payment's state, order and amount with Razorpay before marking anything paid.
 */
exports.verifyPayment = async (user, { orderId, razorpay_order_id: rzpOrderIdFromClient, razorpay_payment_id: paymentId, razorpay_signature: signature }) => {
  const order = await ownOrder(user.id, orderId);
  const storedRzpOrderId = order.payment?.razorpayOrderId;
  if (order.payment?.method !== 'razorpay' || !storedRzpOrderId) throw new AppError('No online payment was started for this order', 422);
  if (rzpOrderIdFromClient !== storedRzpOrderId) throw new AppError('Payment does not belong to this order', 400);

  const secret = process.env.RAZORPAY_KEY_SECRET;
  if (!secret) throw new AppError('Online payments are not configured', 503, 'PAYMENTS_NOT_CONFIGURED');
  // Per Razorpay: use the order id stored on OUR server, never the one echoed by Checkout.
  const expected = hmacHex(secret, `${storedRzpOrderId}|${paymentId}`);
  if (!safeEqualHex(expected, signature)) {
    logger.warn(`Invalid Razorpay signature for order ${order._id}`);
    throw new AppError('Invalid payment signature', 400, 'INVALID_SIGNATURE');
  }

  // Already settled by an earlier verify/webhook: idempotent success.
  if (order.payment.status === 'paid') return view(order);

  let payment;
  try {
    payment = await getRazorpay().payments.fetch(paymentId);
  } catch (e) {
    // Signature is valid but we could not confirm capture. Leave it pending; the webhook will finalise.
    logger.warn(`Could not confirm payment ${paymentId} with Razorpay (${e?.statusCode || e?.message}); awaiting webhook`);
    await Order.updateOne({ _id: order._id, 'payment.status': { $ne: 'paid' } }, { $set: { 'payment.razorpayPaymentId': paymentId } });
    return { ...view(order), paymentStatus: 'pending', note: 'awaiting confirmation' };
  }

  if (payment.order_id !== storedRzpOrderId || payment.amount !== order.payment.amountPaise || payment.currency !== CURRENCY) {
    logger.warn(`Payment ${paymentId} does not match order ${order._id} (order/amount/currency mismatch)`);
    throw new AppError('Payment details do not match this order', 400, 'PAYMENT_MISMATCH');
  }
  if (payment.status === 'captured') {
    const { order: paid } = await markPaid(order, paymentId);
    return view(paid);
  }
  if (payment.status === 'failed') {
    await markFailed(order, payment.error_description);
    return { ...view(order), paymentStatus: 'failed' };
  }
  // 'authorized' (not captured yet) or 'created': wait for payment.captured.
  await Order.updateOne({ _id: order._id, 'payment.status': { $ne: 'paid' } }, { $set: { 'payment.razorpayPaymentId': paymentId } });
  return { ...view(order), paymentStatus: 'pending', note: `payment is ${payment.status}` };
};

/** Backend truth for the UI to poll after Checkout closes. */
exports.paymentStatus = async (user, orderId) => view(await ownOrder(user.id, orderId));

/**
 * Razorpay webhook. `rawBody` MUST be the exact bytes received (signature is over the raw body).
 * Returns { ok, ... } for anything that was authentic (even if ignored) so Razorpay stops retrying;
 * throws on bad signature (400) or internal failure (so Razorpay retries).
 */
exports.handleWebhook = async (rawBody, signature, eventIdHeader) => {
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (!secret) throw new AppError('Webhook secret not configured', 503, 'PAYMENTS_NOT_CONFIGURED');
  if (!Buffer.isBuffer(rawBody) || !rawBody.length) throw new AppError('Empty webhook body', 400);
  if (!safeEqualHex(hmacHex(secret, rawBody), signature)) {
    logger.warn('Razorpay webhook with invalid signature rejected');
    throw new AppError('Invalid webhook signature', 400, 'INVALID_SIGNATURE');
  }

  let event;
  try { event = JSON.parse(rawBody.toString('utf8')); } catch { throw new AppError('Malformed webhook body', 400); }

  // Idempotency: the event id header is unique per event; fall back to a body hash if it is missing.
  const eventId = eventIdHeader || `body:${crypto.createHash('sha256').update(rawBody).digest('hex')}`;
  try {
    await PaymentEvent.create({ eventId, type: event.event });
  } catch (e) {
    if (e.code === 11000) return { ok: true, duplicate: true };
    throw e;
  }

  try {
    return await applyEvent(event);
  } catch (err) {
    await PaymentEvent.deleteOne({ eventId }).catch(() => {}); // let Razorpay's retry be processed
    throw err;
  }
};

async function applyEvent(event) {
  const payment = event.payload?.payment?.entity;
  const rzpOrderId = payment?.order_id || event.payload?.order?.entity?.id;
  if (!rzpOrderId) return { ok: true, ignored: 'no order' };

  const order = await Order.findOne({ 'payment.razorpayOrderId': rzpOrderId });
  if (!order) return { ok: true, ignored: 'unknown order' }; // not one of ours

  switch (event.event) {
    case 'payment.captured':
    case 'order.paid': {
      if (!payment?.id) return { ok: true, ignored: 'no payment' };
      if (payment.amount !== order.payment.amountPaise || payment.currency !== CURRENCY) {
        logger.warn(`Webhook ${event.event}: amount/currency mismatch for order ${order._id}; not marking paid`);
        return { ok: true, ignored: 'amount mismatch' };
      }
      const { changed } = await markPaid(order, payment.id);
      return { ok: true, paid: true, changed };
    }
    case 'payment.failed':
      if (payment?.id) await markFailed(order, payment.error_description);
      return { ok: true, failed: true };
    default:
      return { ok: true, ignored: event.event };
  }
}

exports._internals = { hmacHex, toPaise, safeEqualHex };
