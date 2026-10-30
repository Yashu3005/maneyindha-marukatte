const Joi = require('joi');

exports.productDescriptionSchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  category: Joi.string().trim().max(80).allow(''),
  details: Joi.string().trim().max(500).allow(''),
  language: Joi.string().valid('English', 'Kannada', 'Hindi', 'Tamil', 'Telugu').default('English'),
});

exports.assistantSchema = Joi.object({
  message: Joi.string().trim().min(1).max(500).required(),
  history: Joi.array().items(Joi.object({
    role: Joi.string().valid('user', 'assistant').required(),
    text: Joi.string().max(1500).allow('').required(),
  })).max(12).default([]),
});
