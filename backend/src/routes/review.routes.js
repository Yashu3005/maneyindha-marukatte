const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const reviewController = require('../controllers/review.controller');

router.get('/product/:productId', reviewController.listForProduct);
router.get('/business/:businessId', reviewController.listForBusiness);

router.post('/',
  requireAuth, requireRole('customer', 'entrepreneur'),
  validate(Joi.object({
    productId: Joi.string().hex().length(24).required(),
    orderId: Joi.string().hex().length(24),
    rating: Joi.number().integer().min(1).max(5).required(),
    comment: Joi.string().max(1000).allow(''),
    images: Joi.array().items(Joi.string().uri()).max(5),
  })),
  reviewController.create);

router.post('/:id/reply',
  requireAuth, requireRole('entrepreneur'),
  validate(Joi.object({ text: Joi.string().max(1000).required() })),
  reviewController.reply);

module.exports = router;
