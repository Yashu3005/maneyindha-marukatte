const paymentService = require('../services/payment.service');
const { ok } = require('../utils/apiResponse');

exports.createOrder = async (req, res, next) => {
  try {
    const data = await paymentService.createPaymentOrder(req.user.id, req.body);
    ok(res, data, 'Razorpay order created', 201);
  } catch (e) {
    next(e);
  }
};

exports.verify = async (req, res, next) => {
  try {
    const data = await paymentService.verifyPayment(req.user.id, req.body);
    ok(res, data, 'Payment verified successfully');
  } catch (e) {
    next(e);
  }
};

exports.webhook = async (req, res, next) => {
  try {
    const signature = req.headers['x-razorpay-signature'];
    const data = await paymentService.handleWebhook(req.rawBody, signature, req.body);
    ok(res, data, 'Webhook processed');
  } catch (e) {
    next(e);
  }
};

exports.myTransactions = async (req, res, next) => {
  try {
    const data = await paymentService.getUserTransactions(req.user.id);
    ok(res, data);
  } catch (e) {
    next(e);
  }
};
