const Joi = require('joi');

exports.productDescriptionSchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  category: Joi.string().trim().max(80).allow(''),
  details: Joi.string().trim().max(500).allow(''),
  language: Joi.string().valid('English', 'Kannada', 'Hindi').default('English'),
});
