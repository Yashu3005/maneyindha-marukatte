const crypto = require('crypto');
const Order = require('../models/Order');
const Product = require('../models/Product');
const AppError = require('../utils/AppError');
const { VALID_TRANSITIONS } = require('../models/Order');

exports.createOrder = async (customerId, { businessId, items, deliveryAddress, isSelfPickup, notes }) => {
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

  const deliveryFee = isSelfPickup ? 0 : 30; // TODO: distance-based in Phase 9
  const total = subtotal + deliveryFee;

  return Order.create({
    orderNumber: `MM${Date.now()}${crypto.randomInt(100, 999)}`,
    customer: customerId,
    business: businessId,
    items: orderItems,
    amounts: { subtotal, deliveryFee, discount: 0, tax: 0, total },
    deliveryAddress,
    isSelfPickup: !!isSelfPickup,
    notes,
    statusHistory: [{ status: 'pending', at: new Date() }],
  });
};

exports.ordersForUser = async (user) => {
  const filter =
    user.role === 'entrepreneur' ? {} : // scoped via business lookup in later phase
    user.role === 'delivery_partner' ? { deliveryPartner: user.id } :
    { customer: user.id };
  return Order.find(filter).sort('-createdAt').limit(50);
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
