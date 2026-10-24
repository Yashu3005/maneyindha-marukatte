const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const cartController = require('../controllers/cart.controller');

// Entrepreneurs can shop too (easy switch to customer mode)
router.use(requireAuth, requireRole('customer', 'entrepreneur'));

router.get('/', cartController.get);
router.post('/items',
  validate(Joi.object({
    productId: Joi.string().hex().length(24).required(),
    quantity: Joi.number().integer().min(1).max(50).default(1),
    variant: Joi.string().max(100),
  })),
  cartController.addItem);
router.patch('/items',
  validate(Joi.object({
    productId: Joi.string().hex().length(24).required(),
    quantity: Joi.number().integer().min(0).max(50).required(),
    variant: Joi.string().max(100),
  })),
  cartController.updateItem);
router.delete('/', cartController.clear);
router.post('/coupon',
  validate(Joi.object({ code: Joi.string().trim().max(30).required() })),
  cartController.applyCoupon);

module.exports = router;
