const Joi = require('joi');

exports.registerSchema = Joi.object({
  name: Joi.string().min(2).max(100).required(),
  email: Joi.string().email(),
  phone: Joi.string().pattern(/^[6-9]\d{9}$/),
  password: Joi.string().min(8).max(128).required(),
  role: Joi.string().valid('customer', 'entrepreneur', 'delivery_partner').default('customer'),
}).or('email', 'phone');

exports.loginSchema = Joi.object({
  email: Joi.string().email(),
  phone: Joi.string(),
  username: Joi.string(),
  password: Joi.string().required(),
}).or('email', 'phone', 'username');

exports.sendOtpSchema = Joi.object({
  email: Joi.string().email().required(),
  purpose: Joi.string().valid('registration', 'login', 'verification').default('verification'),
});

exports.verifyOtpSchema = Joi.object({
  email: Joi.string().email().required(),
  otp: Joi.string().trim().length(6).pattern(/^\d{6}$/).required(),
  purpose: Joi.string().valid('registration', 'login', 'verification').default('verification'),
});
