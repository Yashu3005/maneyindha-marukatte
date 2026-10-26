const payment = require('../services/payment.service');
const { ok } = require('../utils/apiResponse');

exports.createOrder = async (req, res, next) => {
  try { ok(res, await payment.createRazorpayOrder(req.user, req.body.orderId), undefined, 201); }
  catch (e) { next(e); }
};

exports.verify = async (req, res, next) => {
  try { ok(res, await payment.verifyPayment(req.user, req.body)); }
  catch (e) { next(e); }
};

exports.status = async (req, res, next) => {
  try { ok(res, await payment.paymentStatus(req.user, req.params.orderId)); }
  catch (e) { next(e); }
};

// Mounted with express.raw(): req.body is the exact Buffer Razorpay signed.
exports.webhook = async (req, res, next) => {
  try {
    const result = await payment.handleWebhook(req.body, req.get('x-razorpay-signature'), req.get('x-razorpay-event-id'));
    res.status(200).json({ success: true, data: result });
  } catch (e) { next(e); }
};
