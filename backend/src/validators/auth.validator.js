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
