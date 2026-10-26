const Joi = require('joi');
const { STATUSES } = require('../models/Order');

const geo = require('./geo.validator');

const objectId = Joi.string().hex().length(24);

exports.createOrderSchema = Joi.object({
  businessId: objectId.required(),
  items: Joi.array().items(Joi.object({
    productId: objectId.required(),
    quantity: Joi.number().integer().min(1).max(50).required(),
  })).min(1).max(50).required(),
  isSelfPickup: Joi.boolean().default(false),
  deliveryAddress: Joi.object({
    line1: Joi.string().trim().min(1).max(200).required(),
    city: Joi.string().trim().max(100).allow(''),
    pincode: Joi.string().trim().max(10).allow(''),
    location: geo.point,
  }).when('isSelfPickup', { is: true, then: Joi.optional(), otherwise: Joi.required() }),
  couponCode: Joi.string().trim().max(30),
  notes: Joi.string().max(500).allow(''),
  paymentMethod: Joi.string().valid('cod', 'razorpay').default('cod'),
});

exports.updateStatusSchema = Joi.object({
  status: Joi.string().valid(...STATUSES).required(),
});
