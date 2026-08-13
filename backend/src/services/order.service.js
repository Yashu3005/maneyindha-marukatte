const crypto = require('crypto');
const Order = require('../models/Order');
const Product = require('../models/Product');
const Cart = require('../models/Cart');
const Coupon = require('../models/Coupon');
const AppError = require('../utils/AppError');
const cartService = require('./cart.service');
const { VALID_TRANSITIONS } = require('../models/Order');

exports.createOrder = async (customerId, { businessId, items, deliveryAddress, isSelfPickup, notes, couponCode }) => {
  if (!items?.length) throw new AppError('Order must contain at least one item', 422);

  // Server-side pricing — never trust client totals.
  const products = await Product.find({ _id: { $in: items.map((i) => i.productId) }, business: businessId, isActive: true });
  const byId = Object.fromEntries(products.map((p) => [String(p._id), p]));

  let subtotal = 0;
  const orderItems = items.map((i) => {
    const p = byId[i.productId];
    if (!p) throw new AppError(`Product ${i.productId} not available`, 422);
    if (p.stock < i.quantity) throw new AppError(`Insufficient stock for ${p.name}`, 422);
    subtotal += p.price * i.quantity;
    return { product: p._id, name: p.name, unitPrice: p.price, quantity: i.quantity };
  });

  // Coupon: re-validated at checkout (cart may hold a stale one)
  let discount = 0;
  let appliedCoupon;
  if (couponCode) {
    const coupon = await cartService.validateCoupon(couponCode, { businessId, subtotal, customerId });
    discount = cartService.computeDiscount(coupon, subtotal);
    appliedCoupon = { code: coupon.code, discount };
    await Coupon.updateOne({ _id: coupon._id }, { $inc: { usedCount: 1 } });
  }

  const deliveryFee = isSelfPickup ? 0 : 30; // TODO: distance-based in Phase 9
  const total = subtotal - discount + deliveryFee;

  // Decrement stock atomically per item
  for (const item of orderItems) {
    const updated = await Product.updateOne(
      { _id: item.product, stock: { $gte: item.quantity } },
      { $inc: { stock: -item.quantity } }
    );
    if (updated.modifiedCount === 0) throw new AppError(`Insufficient stock for ${item.name}`, 422);
  }

  const order = await Order.create({
    orderNumber: `MM${Date.now()}${crypto.randomInt(100, 999)}`,
    customer: customerId,
    business: businessId,
    items: orderItems,
    amounts: { subtotal, deliveryFee, discount, tax: 0, total },
    coupon: appliedCoupon,
    deliveryAddress,
    isSelfPickup: !!isSelfPickup,
    notes,
    statusHistory: [{ status: 'pending', at: new Date() }],
  });

  // Clear cart after successful order
  await Cart.findOneAndUpdate({ customer: customerId }, { items: [], business: undefined, coupon: undefined });

  return order;
};

exports.ordersForUser = async (user) => {
  let filter;
  if (user.role === 'entrepreneur') {
    const Business = require('../models/Business');
    const owned = await Business.find({ owner: user.id }).select('_id');
    // Orders received by their shops + orders they placed while shopping
    filter = { $or: [{ business: { $in: owned.map((b) => b._id) } }, { customer: user.id }] };
  } else if (user.role === 'delivery_partner') {
    filter = { deliveryPartner: user.id };
  } else {
    filter = { customer: user.id };
  }
  return Order.find(filter).sort('-createdAt').limit(50).populate('business', 'name');
};

exports.transition = async (orderId, nextStatus, user) => {
  const order = await Order.findById(orderId);
  if (!order) throw new AppError('Order not found', 404);

  const allowed = VALID_TRANSITIONS[order.status] || [];
  if (!allowed.includes(nextStatus)) {
    throw new AppError(`Invalid transition ${order.status} -> ${nextStatus}`, 422);
  }

  order.status = nextStatus;
  order.statusHistory.push({ status: nextStatus, at: new Date(), by: user.id });
  await order.save();
  return order;
};
