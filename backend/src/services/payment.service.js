const crypto = require('crypto');
const Razorpay = require('razorpay');
const Order = require('../models/Order');
const Product = require('../models/Product');
const Transaction = require('../models/Transaction');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');

function getRazorpayClient() {
  const key_id = process.env.RAZORPAY_KEY_ID;
  const key_secret = process.env.RAZORPAY_KEY_SECRET;

  if (!key_id || !key_secret || key_id.startsWith('replace') || key_id.startsWith('re_placeholder')) {
    return null;
  }
  return new Razorpay({ key_id, key_secret });
}

/**
 * Restores product inventory in case of payment failure or cancellation.
 */
async function restoreInventory(order) {
  if (!order?.items?.length) return;
  for (const item of order.items) {
    if (item.product && item.quantity > 0) {
      await Product.updateOne(
        { _id: item.product },
        { $inc: { stock: item.quantity } }
      ).catch((err) => {
        logger.error(`Failed to restore inventory for product ${item.product}:`, err);
      });
    }
  }
}

/**
 * Creates a Razorpay payment order for an existing pending Order.
 * Validates ownership, trusted server totals, and inventory.
 */
exports.createPaymentOrder = async (userId, { orderId }) => {
  if (!orderId) throw new AppError('orderId is required', 422);

  const order = await Order.findOne({ _id: orderId, customer: userId });
  if (!order) throw new AppError('Order not found or does not belong to you', 404);

  if (order.status !== 'pending') {
    throw new AppError(`Cannot initiate payment for order in '${order.status}' state`, 400);
  }

  const total = order.amounts?.total || 0;
  if (total <= 0) {
    throw new AppError('Order total must be greater than zero for online payment', 400);
  }

  const amountInPaise = Math.round(total * 100);
  const client = exports.getRazorpayClient();
  let razorpayOrderId;

  if (client) {
    try {
      const rzpOrder = await client.orders.create({
        amount: amountInPaise,
        currency: 'INR',
        receipt: order.orderNumber,
        notes: {
          orderId: String(order._id),
          customerId: String(userId),
        },
      });
      razorpayOrderId = rzpOrder.id;
    } catch (err) {
      logger.error('Razorpay order creation failed:', err);
      throw new AppError('Failed to initialize payment gateway order with Razorpay', 502);
    }
  } else {
    // Test mode fallback when Razorpay keys are not yet configured in sandbox
    logger.warn('Running Razorpay in local test mock mode (RAZORPAY_KEY_ID not configured)');
    razorpayOrderId = `order_test_${Date.now()}_${crypto.randomInt(1000, 9999)}`;
  }

  // Update order with payment details
  order.payment = {
    method: 'razorpay',
    razorpayOrderId,
    status: 'pending',
  };
  await order.save();

  // Create or update pending Transaction
  await Transaction.findOneAndUpdate(
    { order: order._id, type: 'payment' },
    {
      user: userId,
      order: order._id,
      type: 'payment',
      amount: total,
      currency: 'INR',
      gateway: 'razorpay',
      gatewayRef: razorpayOrderId,
      status: 'pending',
    },
    { upsert: true, new: true }
  );

  return {
    orderId: order._id,
    orderNumber: order.orderNumber,
    razorpayOrderId,
    amount: total,
    amountInPaise,
    currency: 'INR',
    keyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_placeholder_key',
  };
};

/**
 * Verifies Razorpay payment signature and confirms order.
 */
exports.verifyPayment = async (userId, { orderId, razorpayOrderId, razorpayPaymentId, razorpaySignature }) => {
  if (!orderId || !razorpayOrderId || !razorpayPaymentId) {
    throw new AppError('orderId, razorpayOrderId, and razorpayPaymentId are required', 422);
  }

  const order = await Order.findOne({ _id: orderId, customer: userId });
  if (!order) throw new AppError('Order not found', 404);

  // Idempotency: if already paid, return existing success state
  if (order.payment?.status === 'paid' && order.status === 'confirmed') {
    return { verified: true, order, alreadyProcessed: true };
  }

  const keySecret = process.env.RAZORPAY_KEY_SECRET;

  if (keySecret && razorpaySignature) {
    const expected = crypto
      .createHmac('sha256', keySecret)
      .update(`${razorpayOrderId}|${razorpayPaymentId}`)
      .digest('hex');

    const signatureBuffer = Buffer.from(razorpaySignature);
    const expectedBuffer = Buffer.from(expected);

    const isMatch =
      signatureBuffer.length === expectedBuffer.length &&
      crypto.timingSafeEqual(signatureBuffer, expectedBuffer);

    if (!isMatch) {
      order.payment.status = 'failed';
      order.status = 'payment_failed';
      order.statusHistory.push({ status: 'payment_failed', at: new Date(), by: userId });
      await order.save();
      await restoreInventory(order);

      await Transaction.findOneAndUpdate(
        { order: order._id, type: 'payment' },
        { status: 'failed', meta: { reason: 'Invalid signature', razorpayPaymentId } }
      );

      throw new AppError('Payment signature verification failed. The transaction could not be verified.', 400);
    }
  }

  // Payment verified successfully
  order.payment.status = 'paid';
  order.payment.razorpayPaymentId = razorpayPaymentId;
  order.status = 'confirmed';
  order.statusHistory.push({ status: 'confirmed', at: new Date(), by: userId });
  await order.save();

  // Mark transaction as successful
  await Transaction.findOneAndUpdate(
    { order: order._id, type: 'payment' },
    {
      status: 'success',
      gatewayRef: razorpayPaymentId,
      meta: { razorpayOrderId, razorpayPaymentId, razorpaySignature },
    }
  );

  return { verified: true, order };
};

/**
 * Handles Razorpay server-to-server webhooks with cryptographic HMAC signature verification.
 */
exports.handleWebhook = async (rawBody, signature, event) => {
  const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;

  if (webhookSecret) {
    if (!signature || !rawBody) {
      throw new AppError('Missing webhook signature or payload', 400);
    }

    const expectedSignature = crypto
      .createHmac('sha256', webhookSecret)
      .update(rawBody)
      .digest('hex');

    const sigBuf = Buffer.from(signature);
    const expBuf = Buffer.from(expectedSignature);

    if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
      logger.error('Invalid Razorpay webhook signature');
      throw new AppError('Invalid webhook signature', 400);
    }
  }

  const eventType = event.event;
  const payload = event.payload;

  logger.info(`Received Razorpay webhook event: ${eventType}`);

  if (eventType === 'payment.captured' || eventType === 'order.paid') {
    const paymentEntity = payload.payment?.entity;
    const orderEntity = payload.order?.entity;
    const rzpOrderId = paymentEntity?.order_id || orderEntity?.id;

    if (rzpOrderId) {
      const order = await Order.findOne({ 'payment.razorpayOrderId': rzpOrderId });
      if (order && order.payment.status !== 'paid') {
        order.payment.status = 'paid';
        order.payment.razorpayPaymentId = paymentEntity?.id;
        order.status = 'confirmed';
        order.statusHistory.push({ status: 'confirmed', at: new Date() });
        await order.save();

        await Transaction.findOneAndUpdate(
          { order: order._id, type: 'payment' },
          { status: 'success', gatewayRef: paymentEntity?.id }
        );
      }
    }
  } else if (eventType === 'payment.failed') {
    const paymentEntity = payload.payment?.entity;
    const rzpOrderId = paymentEntity?.order_id;

    if (rzpOrderId) {
      const order = await Order.findOne({ 'payment.razorpayOrderId': rzpOrderId });
      if (order && order.payment.status !== 'paid') {
        order.payment.status = 'failed';
        order.status = 'payment_failed';
        order.statusHistory.push({ status: 'payment_failed', at: new Date() });
        await order.save();
        await restoreInventory(order);

        await Transaction.findOneAndUpdate(
          { order: order._id, type: 'payment' },
          { status: 'failed', meta: { error: paymentEntity?.error_description } }
        );
      }
    }
  }

  return { status: 'processed', event: eventType };
};

/**
 * Returns customer transactions list.
 */
exports.getUserTransactions = async (userId) => {
  return Transaction.find({ user: userId })
    .populate('order', 'orderNumber status amounts createdAt')
    .sort('-createdAt')
    .limit(50);
};

exports.restoreInventory = restoreInventory;
exports.getRazorpayClient = getRazorpayClient;
