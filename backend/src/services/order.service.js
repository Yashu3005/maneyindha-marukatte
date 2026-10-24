const crypto = require('crypto');
const Order = require('../models/Order');
const Product = require('../models/Product');
const Cart = require('../models/Cart');
const Coupon = require('../models/Coupon');
const Business = require('../models/Business');
const Notification = require('../models/Notification');
const AppError = require('../utils/AppError');
const cartService = require('./cart.service');
const { VALID_TRANSITIONS } = require('../models/Order');

exports.createOrder = async (
  customerId,
  { businessId, items, deliveryAddress, isSelfPickup, notes, couponCode, paymentMethod }
) => {
  if (!items?.length) throw new AppError('Order must contain at least one item', 422);

  // Verify business is open
  const business = await Business.findById(businessId);
  if (!business || !business.isActive) throw new AppError('Business not found or inactive', 404);
  if (business.isOpen === false) {
    throw new AppError('Store is currently closed and not accepting orders', 422);
  }

  // Server-side pricing — never trust client totals.
  const products = await Product.find({
    _id: { $in: items.map((i) => i.productId) },
    business: businessId,
    isActive: true,
  });
  const byId = Object.fromEntries(products.map((p) => [String(p._id), p]));

  let subtotal = 0;
  let deliveryFee = isSelfPickup ? 0 : (business.deliveryCharge || 30);

  const orderItems = items.map((i) => {
    const p = byId[i.productId];
    if (!p) throw new AppError(`Product ${i.productId} not available`, 422);
    if (p.stock < i.quantity) throw new AppError(`Insufficient stock for ${p.name}`, 422);
    subtotal += p.price * i.quantity;

    // Use product-specific delivery settings if available
    if (!isSelfPickup && p.deliveryOptions) {
      if (p.deliveryOptions.freeDelivery) deliveryFee = 0;
      else if (p.deliveryOptions.deliveryCharge !== undefined) deliveryFee = p.deliveryOptions.deliveryCharge;
    }

    return {
      product: p._id,
      name: p.name,
      variant: i.variant,
      customization: i.customization || '',
      unitPrice: p.price,
      quantity: i.quantity,
    };
  });

  // Coupon: re-validated at checkout
  let discount = 0;
  let appliedCoupon;
  if (couponCode) {
    const coupon = await cartService.validateCoupon(couponCode, { businessId, subtotal, customerId });
    discount = cartService.computeDiscount(coupon, subtotal);
    appliedCoupon = { code: coupon.code, discount };
    await Coupon.updateOne({ _id: coupon._id }, { $inc: { usedCount: 1 } });
  }

  const total = subtotal - discount + deliveryFee;

  // Decrement stock atomically per item and increment ordersCount
  for (const item of orderItems) {
    const updated = await Product.updateOne(
      { _id: item.product, stock: { $gte: item.quantity } },
      { $inc: { stock: -item.quantity, ordersCount: item.quantity } }
    );
    if (updated.modifiedCount === 0) throw new AppError(`Insufficient stock for ${item.name}`, 422);
  }

  const method = paymentMethod === 'online' ? 'upi' : 'cod';
  const payStatus = method === 'cod' ? 'pending' : 'paid';

  const order = await Order.create({
    orderNumber: `MM${Date.now().toString().slice(-6)}${crypto.randomInt(100, 999)}`,
    customer: customerId,
    business: businessId,
    items: orderItems,
    amounts: { subtotal, deliveryFee, discount, tax: 0, total },
    coupon: appliedCoupon,
    payment: {
      method,
      status: payStatus,
    },
    deliveryAddress,
    isSelfPickup: !!isSelfPickup,
    notes,
    status: 'pending',
    statusHistory: [{ status: 'pending', at: new Date(), by: customerId }],
  });

  // Clear cart after successful order
  await Cart.findOneAndUpdate({ customer: customerId }, { items: [], business: undefined, coupon: undefined });

  // Notify entrepreneur
  await Notification.create({
    user: business.owner,
    type: 'order',
    title: 'New Order Received! 🌸',
    body: `New order #${order.orderNumber} placed for ₹${total}.`,
    data: { orderId: String(order._id) },
  });

  // Notify customer
  await Notification.create({
    user: customerId,
    type: 'order',
    title: 'Order Confirmed! 🎉',
    body: `Your order #${order.orderNumber} has been received by ${business.name}.`,
    data: { orderId: String(order._id) },
  });

  return order;
};

exports.getOrderById = async (orderId, user) => {
  const order = await Order.findById(orderId)
    .populate('business', 'name slug address rating isOpen')
    .populate('customer', 'name phone email');
  if (!order) throw new AppError('Order not found', 404);

  // Security: users can only view their own order or an order for their owned shop
  if (user.role !== 'admin' && user.role !== 'super_admin') {
    const isCustomer = String(order.customer._id || order.customer) === user.id;
    let isOwner = false;
    if (user.role === 'entrepreneur') {
      isOwner = await Business.exists({ _id: order.business._id || order.business, owner: user.id });
    }
    if (!isCustomer && !isOwner) throw new AppError('Unauthorized to view this order', 403);
  }

  return order;
};

exports.ordersForUser = async (user) => {
  let filter;
  if (user.role === 'entrepreneur') {
    const owned = await Business.find({ owner: user.id }).select('_id');
    filter = { $or: [{ business: { $in: owned.map((b) => b._id) } }, { customer: user.id }] };
  } else if (user.role === 'delivery_partner') {
    filter = { deliveryPartner: user.id };
  } else {
    filter = { customer: user.id };
  }
  return Order.find(filter)
    .sort('-createdAt')
    .limit(50)
    .populate('business', 'name rating address')
    .populate('customer', 'name phone');
};

exports.transition = async (orderId, nextStatus, user) => {
  const order = await Order.findById(orderId).populate('business', 'name owner');
  if (!order) throw new AppError('Order not found', 404);

  const allowed = VALID_TRANSITIONS[order.status] || [];
  if (!allowed.includes(nextStatus)) {
    throw new AppError(`Invalid transition ${order.status} -> ${nextStatus}`, 422);
  }

  order.status = nextStatus;
  order.statusHistory.push({ status: nextStatus, at: new Date(), by: user.id });
  await order.save();

  // Notify customer of status change
  const statusMessages = {
    confirmed: 'Your order has been confirmed.',
    preparing: 'Your order is now being prepared.',
    ready: order.isSelfPickup ? 'Your order is ready for pickup!' : 'Your order is packed and ready.',
    picked_up: 'Your order has been picked up.',
    out_for_delivery: 'Your order is out for delivery.',
    delivered: order.isSelfPickup ? 'Your order has been picked up.' : 'Your order has been delivered.',
    cancelled: 'Your order has been cancelled.',
  };

  if (statusMessages[nextStatus]) {
    await Notification.create({
      user: order.customer,
      type: 'order',
      title: `Order Status: ${nextStatus.replace('_', ' ').toUpperCase()}`,
      body: statusMessages[nextStatus],
      data: { orderId: String(order._id), status: nextStatus },
    });
  }

  return order;
};

exports.cancelOrder = async (orderId, customerId) => {
  const order = await Order.findOne({ _id: orderId, customer: customerId });
  if (!order) throw new AppError('Order not found', 404);

  if (!['pending', 'confirmed'].includes(order.status)) {
    throw new AppError('This order cannot be cancelled because preparation has already started.', 422);
  }

  order.status = 'cancelled';
  if (order.payment?.status === 'paid') {
    order.payment.status = 'refund_in_progress';
  }
  order.statusHistory.push({ status: 'cancelled', at: new Date(), by: customerId });
  await order.save();

  // Restore stock
  for (const it of order.items) {
    await Product.updateOne({ _id: it.product }, { $inc: { stock: it.quantity } });
  }

  await Notification.create({
    user: customerId,
    type: 'order',
    title: 'Order Cancelled',
    body: 'Your order has been cancelled successfully.',
    data: { orderId: String(order._id) },
  });

  return order;
};

exports.requestAfterSales = async (orderId, customerId, { type, reason, description, images }) => {
  const order = await Order.findOne({ _id: orderId, customer: customerId });
  if (!order) throw new AppError('Order not found', 404);
  if (order.status !== 'delivered') {
    throw new AppError('After-sales requests can only be raised for delivered orders', 422);
  }

  // AI suggestion rule
  let aiSuggestion = 'Consider customer explanation and photos before approval.';
  const lower = (reason || '').toLowerCase();
  if (lower.includes('damage') || lower.includes('wrong')) {
    aiSuggestion = 'Images show potential issue. Recommended action: Approve request and initiate return if item needed.';
  } else if (lower.includes('quality')) {
    aiSuggestion = 'Review product preparation standards. Consider offering replacement.';
  }

  order.afterSales = {
    isRequested: true,
    type,
    reason,
    description,
    images: images || [],
    requestedAt: new Date(),
    status: 'requested',
    returnRequired: false,
    returnStatus: 'none',
    aiSuggestion,
  };

  await order.save();

  // Notify entrepreneur
  const business = await Business.findById(order.business);
  if (business) {
    await Notification.create({
      user: business.owner,
      type: 'refund',
      title: `${type === 'refund' ? 'Refund' : 'Replacement'} Request Raised`,
      body: `Customer requested ${type} for order #${order.orderNumber}. Reason: ${reason}`,
      data: { orderId: String(order._id) },
    });
  }

  return order;
};

exports.decideAfterSales = async (orderId, entrepreneurId, { decision, rejectionReason, returnRequired }) => {
  const order = await Order.findById(orderId).populate('business');
  if (!order) throw new AppError('Order not found', 404);

  if (String(order.business.owner) !== String(entrepreneurId)) {
    throw new AppError('Unauthorized: not the owner of this store', 403);
  }

  order.afterSales.decidedAt = new Date();
  order.afterSales.entrepreneurDecision = decision;

  if (decision === 'approved') {
    if (returnRequired) {
      order.afterSales.returnRequired = true;
      order.afterSales.returnStatus = 'return_required';
      order.afterSales.status = 'return_required';
    } else {
      order.afterSales.status = order.afterSales.type === 'refund' ? 'refund_completed' : 'replacement_shipped';
      if (order.afterSales.type === 'refund') order.payment.status = 'refund_completed';
    }
  } else if (decision === 'rejected') {
    order.afterSales.status = 'rejected';
    order.afterSales.rejectionReason = rejectionReason || 'Request does not meet return policy criteria.';
  }

  await order.save();

  // Notify customer
  await Notification.create({
    user: order.customer,
    type: 'refund',
    title: `${order.afterSales.type === 'refund' ? 'Refund' : 'Replacement'} ${decision === 'approved' ? 'Approved' : 'Rejected'}`,
    body: decision === 'approved'
      ? returnRequired
        ? 'Your request was approved. Please initiate the return of the item.'
        : 'Your request has been approved and is being completed.'
      : `Your request was rejected: ${order.afterSales.rejectionReason}`,
    data: { orderId: String(order._id) },
  });

  return order;
};

exports.startReturn = async (orderId, customerId) => {
  const order = await Order.findOne({ _id: orderId, customer: customerId });
  if (!order) throw new AppError('Order not found', 404);

  if (order.afterSales.returnStatus !== 'return_required') {
    throw new AppError('Return is not required or already initiated', 422);
  }

  order.afterSales.returnStatus = 'return_initiated';
  order.afterSales.status = 'return_initiated';
  await order.save();

  return order;
};

exports.confirmReturn = async (orderId, entrepreneurId) => {
  const order = await Order.findById(orderId).populate('business');
  if (!order) throw new AppError('Order not found', 404);

  if (String(order.business.owner) !== String(entrepreneurId)) {
    throw new AppError('Unauthorized', 403);
  }

  order.afterSales.returnStatus = 'return_received';
  if (order.afterSales.type === 'refund') {
    order.afterSales.status = 'refund_completed';
    order.payment.status = 'refund_completed';
  } else {
    order.afterSales.status = 'replacement_shipped';
  }

  await order.save();

  await Notification.create({
    user: order.customer,
    type: 'refund',
    title: 'Return Received',
    body: `The entrepreneur received the returned item. ${order.afterSales.type === 'refund' ? 'Refund completed.' : 'Replacement shipped.'}`,
    data: { orderId: String(order._id) },
  });

  return order;
};

exports.getAfterSalesForEntrepreneur = async (user) => {
  const owned = await Business.find({ owner: user.id }).select('_id');
  return Order.find({
    business: { $in: owned.map((b) => b._id) },
    'afterSales.isRequested': true,
  })
    .sort('-afterSales.requestedAt')
    .populate('customer', 'name phone email');
};
