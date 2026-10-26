const Joi = require('joi');

const objectId = Joi.string().hex().length(24);

exports.createRazorpayOrderSchema = Joi.object({ orderId: objectId.required() });

exports.verifyPaymentSchema = Joi.object({
  orderId: objectId.required(),
  razorpay_order_id: Joi.string().trim().max(60).required(),
  razorpay_payment_id: Joi.string().trim().max(60).required(),
  razorpay_signature: Joi.string().trim().length(64).hex().required(),
});
