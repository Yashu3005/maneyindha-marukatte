const crypto = require('crypto');
const Order = require('../models/Order');
const Product = require('../models/Product');
const Business = require('../models/Business');
const Cart = require('../models/Cart');
const Coupon = require('../models/Coupon');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');
const cartService = require('./cart.service');
const { VALID_TRANSITIONS } = require('../models/Order');

const ADMIN_ROLES = ['admin', 'super_admin'];

// Self-pickup orders never travel: once ready, the customer collects it and the shop marks it collected
// (stored as 'delivered' so ratings and rewards work the same way).
const PICKUP_TRANSITIONS = { ...VALID_TRANSITIONS, ready: ['delivered'] };

// While Razorpay runs in TEST mode no real money moves, so shops may confirm an order whose payment is still
// pending. It switches itself off with live keys (rzp_live_...); ALLOW_CONFIRM_WITHOUT_PAYMENT=true forces it on.
const paymentGateOpen = () =>
  process.env.ALLOW_CONFIRM_WITHOUT_PAYMENT === 'true' || /^rzp_test_/.test(process.env.RAZORPAY_KEY_ID || '');

// Statuses each participant may move an order INTO. Whether the move is legal
// from the current state is decided separately by VALID_TRANSITIONS.
const OWNER_TARGETS = ['confirmed', 'rejected', 'cancelled', 'preparing', 'ready', 'picked_up', 'out_for_delivery', 'delivered'];
const PARTNER_TARGETS = ['picked_up', 'out_for_delivery', 'delivered'];
const CUSTOMER_CANCELLABLE_FROM = ['pending', 'confirmed'];
// Stock (and coupon use) are reserved at creation and released when an order dies.
const RELEASING_STATUSES = ['cancelled', 'rejected', 'payment_failed'];

async function releaseStock(items) {
  await Promise.all(items.map((i) =>
    Product.updateOne({ _id: i.product }, { $inc: { stock: i.quantity } })
      .catch((e) => logger.error(`stock rollback failed for ${i.product}: ${e.message}`))));
}

async function releaseCoupon(couponId) {
  await Coupon.updateOne({ _id: couponId, usedCount: { $gt: 0 } }, { $inc: { usedCount: -1 } })
    .catch((e) => logger.error(`coupon rollback failed for ${couponId}: ${e.message}`));
}

exports.createOrder = async (customerId, { businessId, items, deliveryAddress, isSelfPickup, notes, couponCode, paymentMethod }) => {
  const method = paymentMethod === 'razorpay' ? 'razorpay' : 'cod';
  if (!items?.length) throw new AppError('Order must contain at least one item', 422);

  const business = await Business.findOne({ _id: businessId, isActive: true, 'verification.status': 'approved' });
  if (!business) throw new AppError('Shop not available', 422);
  if (business.isOpen === false) throw new AppError('Shop is currently closed', 422);

  // Merge duplicate lines so stock checks and pricing see the real total.
  const qtyById = new Map();
  for (const i of items) {
    const q = Number(i.quantity);
    if (!Number.isInteger(q) || q < 1) throw new AppError('Quantity must be a positive whole number', 422);
    qtyById.set(String(i.productId), (qtyById.get(String(i.productId)) || 0) + q);
  }

  // Server-side pricing — never trust client totals.
  const products = await Product.find({ _id: { $in: [...qtyById.keys()] }, business: businessId, isActive: true });
  const byId = Object.fromEntries(products.map((p) => [String(p._id), p]));

  let subtotal = 0;
  const orderItems = [...qtyById].map(([productId, quantity]) => {
    const p = byId[productId];
    if (!p) throw new AppError(`Product ${productId} not available`, 422);
    if (p.stock < quantity) throw new AppError(`Insufficient stock for ${p.name}`, 422);
    subtotal += p.price * quantity;
    return { product: p._id, name: p.name, unitPrice: p.price, quantity };
  });

  // Coupon: re-validated at checkout (cart may hold a stale one)
  let discount = 0;
  let coupon;
  let appliedCoupon;
  if (couponCode) {
    coupon = await cartService.validateCoupon(couponCode, { businessId, subtotal, customerId });
    discount = cartService.computeDiscount(coupon, subtotal);
    appliedCoupon = { code: coupon.code, discount };
  }

  const deliveryFee = isSelfPickup ? 0 : 30; // TODO: distance-based in Phase 9
  const total = subtotal - discount + deliveryFee;

  // No multi-document transaction (works on standalone Mongo), so reserve stock and
  // the coupon first, create the order, and compensate if anything fails.
  const reserved = [];
  let couponReserved = false;
  let order;
  try {
    for (const item of orderItems) {
      const updated = await Product.updateOne(
        { _id: item.product, stock: { $gte: item.quantity } },
        { $inc: { stock: -item.quantity } }
      );
      if (updated.modifiedCount === 0) throw new AppError(`Insufficient stock for ${item.name}`, 422);
      reserved.push(item);
    }

    if (coupon) {
      const filter = { _id: coupon._id };
      if (coupon.usageLimitTotal) filter.usedCount = { $lt: coupon.usageLimitTotal };
      const res = await Coupon.updateOne(filter, { $inc: { usedCount: 1 } });
      if (res.modifiedCount === 0) throw new AppError('Coupon usage limit reached', 422);
      couponReserved = true;
    }

    order = await Order.create({
      orderNumber: `MM${Date.now()}${crypto.randomInt(100, 999)}`,
      customer: customerId,
      business: businessId,
      items: orderItems,
      amounts: { subtotal, deliveryFee, discount, tax: 0, total },
      coupon: appliedCoupon,
      deliveryAddress: isSelfPickup ? undefined : deliveryAddress,
      isSelfPickup: !!isSelfPickup,
      notes,
      payment: { method, status: 'pending' },
      statusHistory: [{ status: 'pending', at: new Date() }],
    });
  } catch (err) {
    await releaseStock(reserved);
    if (couponReserved) await releaseCoupon(coupon._id);
    throw err;
  }

  // Clear cart after successful order
  await Cart.findOneAndUpdate({ customer: customerId }, { items: [], business: undefined, coupon: undefined });

  return order;
};

// Orders the user PLACED. An entrepreneur who shops as a customer sees their purchases here, never shop orders.
exports.ordersForUser = async (user) => {
  const filter = user.role === 'delivery_partner' ? { deliveryPartner: user.id } : { customer: user.id };
  return Order.find(filter).sort('-createdAt').limit(50).populate('business', 'name').populate('items.product', 'images');
};

// Orders RECEIVED by the shops this user owns (and nothing else), with who to hand each one to.
// Shop owners get the customer's name and phone only, never the email.
exports.receivedOrders = async (user) => {
  const owned = await Business.find({ owner: user.id }).select('_id');
  if (!owned.length) return [];
  return Order.find({ business: { $in: owned.map((b) => b._id) } })
    .sort('-createdAt').limit(100)
    .populate('business', 'name')
    .populate('items.product', 'images')
    .populate('customer', 'name phone');
};

exports.transition = async (orderId, nextStatus, user) => {
  const order = await Order.findById(orderId);
  if (!order) throw new AppError('Order not found', 404);

  // Who is this user relative to the order?
  const isAdmin = ADMIN_ROLES.includes(user.role);
  const isCustomer = String(order.customer) === String(user.id);
  const isPartner = !!order.deliveryPartner && String(order.deliveryPartner) === String(user.id);
  const isShopOwner = !!(await Business.exists({ _id: order.business, owner: user.id }));

  // Non-participants get 404 so order ids cannot be probed.
  if (!isAdmin && !isCustomer && !isPartner && !isShopOwner) throw new AppError('Order not found', 404);

  const permitted =
    isAdmin ||
    (isShopOwner && OWNER_TARGETS.includes(nextStatus)) ||
    (isPartner && PARTNER_TARGETS.includes(nextStatus)) ||
    (isCustomer && nextStatus === 'cancelled' && CUSTOMER_CANCELLABLE_FROM.includes(order.status));
  if (!permitted) throw new AppError('You are not allowed to make this status change', 403);

  // An online-payment order is only accepted by the shop once the payment is confirmed (server-side).
  if (nextStatus === 'confirmed' && order.payment?.method === 'razorpay' && order.payment.status !== 'paid') {
    if (!paymentGateOpen()) throw new AppError('Payment for this order has not been confirmed yet', 409, 'PAYMENT_PENDING');
    logger.warn(`Order ${order._id} confirmed without a confirmed payment (payment test mode)`);
  }

  const allowed = (order.isSelfPickup ? PICKUP_TRANSITIONS : VALID_TRANSITIONS)[order.status] || [];
  if (!allowed.includes(nextStatus)) {
    throw new AppError(`Invalid transition ${order.status} -> ${nextStatus}`, 422);
  }

  // Compare-and-set on the current status so two concurrent requests can't both win.
  const updated = await Order.findOneAndUpdate(
    { _id: order._id, status: order.status },
    { $set: { status: nextStatus }, $push: { statusHistory: { status: nextStatus, at: new Date(), by: user.id } } },
    { new: true }
  );
  if (!updated) throw new AppError('Order status changed, please retry', 409);

  // Money was taken online but the order will not be fulfilled: flag it for a (manual) refund.
  if (RELEASING_STATUSES.includes(nextStatus) && order.payment?.status === 'paid') {
    await Order.updateOne({ _id: order._id }, { $set: { 'payment.needsRefund': true } });
    logger.warn(`Order ${order._id} ${nextStatus} after online payment; manual refund needed`);
  }

  if (RELEASING_STATUSES.includes(nextStatus)) {
    await releaseStock(order.items);
    if (order.coupon?.code) {
      const coupon = await Coupon.findOne({ code: order.coupon.code }).select('_id');
      if (coupon) await releaseCoupon(coupon._id);
    }
  }
  return updated;
};
