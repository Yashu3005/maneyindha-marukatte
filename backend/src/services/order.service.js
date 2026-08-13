const crypto = require('crypto');
const Order = require('../models/Order');
const Product = require('../models/Product');
const Cart = require('../models/Cart');
const Coupon = require('../models/Coupon');
const User = require('../models/User');
const Notification = require('../models/Notification');
const AppError = require('../utils/AppError');
const cartService = require('./cart.service');
const { VALID_TRANSITIONS } = require('../models/Order');

async function notify(userId, type, title, body, data) {
  try { await Notification.create({ user: userId, type, title, body, data }); }
  catch { /* notifications must never break the main flow */ }
}

exports.createOrder = async (customerId, { businessId, items, deliveryAddress, isSelfPickup, notes, couponCode, useCoins }) => {
  if (!items?.length) throw new AppError('Order must contain at least one item', 422);

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

  let discount = 0;
  let appliedCoupon;
  if (couponCode) {
    const coupon = await cartService.validateCoupon(couponCode, { businessId, subtotal, customerId });
    discount = cartService.computeDiscount(coupon, subtotal);
    appliedCoupon = { code: coupon.code, discount };
    await Coupon.updateOne({ _id: coupon._id }, { $inc: { usedCount: 1 } });
  }

  // Loyalty coins: 1 coin = ₹1, redeemable against the item total.
  let coinsUsed = 0;
  if (useCoins) {
    const user = await User.findById(customerId);
    coinsUsed = Math.min(user?.coins || 0, Math.max(subtotal - discount, 0));
    if (coinsUsed > 0) {
      await User.updateOne({ _id: customerId, coins: { $gte: coinsUsed } }, { $inc: { coins: -coinsUsed } });
    }
  }

  const deliveryFee = isSelfPickup ? 0 : 30;
  const total = subtotal - discount - coinsUsed + deliveryFee;

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
    amounts: { subtotal, deliveryFee, discount: discount + coinsUsed, tax: 0, total },
    coupon: appliedCoupon,
    coinsUsed,
    deliveryAddress,
    deliveryOtp: String(crypto.randomInt(1000, 9999)),
    isSelfPickup: !!isSelfPickup,
    notes,
    statusHistory: [{ status: 'pending', at: new Date() }],
  });

  await Cart.findOneAndUpdate({ customer: customerId }, { items: [], business: undefined, coupon: undefined });

  // Tell the shop owner
  const Business = require('../models/Business');
  const shop = await Business.findById(businessId).select('owner name');
  if (shop) {
    await notify(shop.owner, 'order', 'New order 🎉',
      `${order.orderNumber} · ₹${total} for ${shop.name}`, { orderId: String(order._id) });
  }
  return order;
};

exports.ordersForUser = async (user, view) => {
  let filter;
  let query;
  if (user.role === 'delivery_partner') {
    filter = { deliveryPartner: user.id };
    query = Order.find(filter);
  } else if (view === 'seller' && user.role === 'entrepreneur') {
    const Business = require('../models/Business');
    const owned = await Business.find({ owner: user.id }).select('_id');
    filter = { business: { $in: owned.map((b) => b._id) } };
    query = Order.find(filter);
  } else {
    filter = { customer: user.id };
    // Buyers see their delivery OTP to hand to the partner.
    query = Order.find(filter).select('+deliveryOtp');
  }
  return query.sort('-createdAt').limit(50).populate('business', 'name');
};

const SELLER_SET = ['confirmed', 'rejected', 'preparing', 'ready'];
const FULFILL_SET = ['picked_up', 'out_for_delivery', 'delivered'];
const CUSTOMER_SET = ['cancelled'];
const STATUS_LABEL = {
  confirmed: 'Your order was confirmed', preparing: 'Your order is being prepared',
  ready: 'Your order is ready', picked_up: 'Your order was picked up',
  out_for_delivery: 'Your order is out for delivery', delivered: 'Your order was delivered 🎉',
  rejected: 'Your order was rejected', cancelled: 'Order cancelled',
};

exports.transition = async (orderId, nextStatus, user, otp) => {
  const order = await Order.findById(orderId).select('+deliveryOtp');
  if (!order) throw new AppError('Order not found', 404);

  const allowed = VALID_TRANSITIONS[order.status] || [];
  if (!allowed.includes(nextStatus)) {
    throw new AppError(`Invalid transition ${order.status} -> ${nextStatus}`, 422);
  }

  const isAdmin = user.role === 'admin' || user.role === 'super_admin';
  if (!isAdmin) {
    if (SELLER_SET.includes(nextStatus)) {
      const Business = require('../models/Business');
      const ownsShop = await Business.exists({ _id: order.business, owner: user.id });
      if (!ownsShop) throw new AppError('Only the shop that received this order can update it', 403);
    } else if (FULFILL_SET.includes(nextStatus)) {
      if (order.deliveryPartner) {
        // A partner took this delivery — only they can progress it.
        if (String(order.deliveryPartner) !== String(user.id)) {
          throw new AppError('Only the assigned delivery partner can update this order', 403);
        }
        if (nextStatus === 'delivered') {
          if (!otp || otp !== order.deliveryOtp) {
            throw new AppError('Delivery OTP incorrect — ask the customer for their code', 422);
          }
        }
      } else {
        // No partner (self pickup / shop delivers): the shop handles it.
        const Business = require('../models/Business');
        const ownsShop = await Business.exists({ _id: order.business, owner: user.id });
        if (!ownsShop) throw new AppError('Only the shop that received this order can update it', 403);
      }
    } else if (CUSTOMER_SET.includes(nextStatus)) {
      if (String(order.customer) !== String(user.id)) {
        throw new AppError('You can only cancel your own orders', 403);
      }
    } else {
      throw new AppError('Not allowed', 403);
    }
  }

  order.status = nextStatus;
  order.statusHistory.push({ status: nextStatus, at: new Date(), by: user.id });
  await order.save();

  await notify(order.customer, 'order',
    STATUS_LABEL[nextStatus] || `Order ${nextStatus}`,
    order.orderNumber, { orderId: String(order._id) });

  // Loyalty: 2% of the total back as coins on delivery.
  if (nextStatus === 'delivered') {
    const earned = Math.floor((order.amounts.total || 0) * 0.02);
    if (earned > 0) {
      await User.updateOne({ _id: order.customer }, { $inc: { coins: earned } });
      await notify(order.customer, 'reward', `You earned ${earned} coins 🪙`,
        'Redeem them on your next order at checkout.', { orderId: String(order._id) });
    }
  }
  return order;
};
