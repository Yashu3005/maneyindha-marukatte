const Razorpay = require('razorpay');
const Order = require('../models/Order');
const Transaction = require('../models/Transaction');
const AppError = require('../utils/AppError');

function client() {
  if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
    throw new AppError('Online payments not configured yet', 503);
  }
  return new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID,
    key_secret: process.env.RAZORPAY_KEY_SECRET,
  });
}

// Creates a Razorpay Payment Link for an order (works great on web —
// no client SDK needed; customer pays on Razorpay's page).
exports.createPaymentLink = async (customerId, orderId, returnUrl) => {
  const order = await Order.findOne({ _id: orderId, customer: customerId });
  if (!order) throw new AppError('Order not found', 404);
  if (order.payment.status === 'paid') throw new AppError('Order already paid', 422);

  const rz = client();
  const link = await rz.paymentLink.create({
    amount: Math.round(order.amounts.total * 100), // paise
    currency: 'INR',
    reference_id: order.orderNumber,
    description: `Maneyindha Marukatte order ${order.orderNumber}`,
    callback_url: returnUrl || 'https://maneyindha-marukatte.vercel.app/#/orders',
    callback_method: 'get',
    notes: { orderId: String(order._id) },
  });

  order.payment.method = 'razorpay';
  order.payment.razorpayOrderId = link.id; // store the payment-link id
  await order.save();
  return { url: link.short_url, linkId: link.id };
};

// Server-side truth: ask Razorpay whether the link was paid.
exports.verifyPayment = async (customerId, orderId) => {
  const order = await Order.findOne({ _id: orderId, customer: customerId });
  if (!order) throw new AppError('Order not found', 404);
  if (!order.payment.razorpayOrderId) throw new AppError('No payment started for this order', 422);
  if (order.payment.status === 'paid') return { paid: true };

  const rz = client();
  const link = await rz.paymentLink.fetch(order.payment.razorpayOrderId);

  if (link.status === 'paid') {
    order.payment.status = 'paid';
    if (link.payments && link.payments[0]) {
      order.payment.razorpayPaymentId = link.payments[0].payment_id;
    }
    await order.save();
    await Transaction.create({
      user: customerId, order: order._id, type: 'payment',
      amount: order.amounts.total, gateway: 'razorpay',
      gatewayRef: order.payment.razorpayPaymentId || order.payment.razorpayOrderId,
      status: 'success',
    });
    return { paid: true };
  }
  return { paid: false, status: link.status };
};
