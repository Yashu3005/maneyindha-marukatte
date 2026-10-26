const Joi = require('joi');

exports.registerSchema = Joi.object({
  name: Joi.string().min(2).max(100).required(),
  email: Joi.string().email().lowercase(),
  phone: Joi.string().pattern(/^[6-9]\d{9}$/),
  password: Joi.string().min(8).max(128).required(),
  role: Joi.string().valid('customer', 'entrepreneur', 'delivery_partner').default('customer'),
}).or('email', 'phone');

exports.loginSchema = Joi.object({
  email: Joi.string().email().lowercase(),
  phone: Joi.string(),
  username: Joi.string().lowercase(),
  password: Joi.string().required(),
}).or('email', 'phone', 'username');

exports.sendOtpSchema = Joi.object({
  email: Joi.string().trim().email().lowercase().max(254).required(),
});

exports.verifyOtpSchema = Joi.object({
  email: Joi.string().trim().email().lowercase().max(254).required(),
  otp: Joi.string().pattern(/^\d{6}$/).required().messages({ 'string.pattern.base': 'otp must be 6 digits' }),
});
