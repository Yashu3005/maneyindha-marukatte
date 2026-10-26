const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const wishlistController = require('../controllers/wishlist.controller');

router.use(requireAuth, requireRole('customer', 'entrepreneur'));

router.get('/', wishlistController.get);
router.post('/products',
  validate(Joi.object({ productId: Joi.string().hex().length(24).required() })),
  wishlistController.toggleProduct);
router.post('/businesses',
  validate(Joi.object({ businessId: Joi.string().hex().length(24).required() })),
  wishlistController.toggleBusiness);

module.exports = router;
