const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole, optionalAuth } = require('../middleware/auth');
const validate = require('../middleware/validate');
const productController = require('../controllers/product.controller');

const objectId = Joi.string().hex().length(24);

router.get('/', optionalAuth, productController.list);      // ?q=&category=&business=&page=&limit=&sort=
router.get('/:id', optionalAuth, productController.getById);
router.post('/', requireAuth, requireRole('entrepreneur'),
  validate(Joi.object({
    business: objectId.required(),
    name: Joi.string().trim().min(1).max(150).required(),
    description: Joi.string().max(3000).allow(''),
    category: objectId,
    images: Joi.array().items(Joi.string().uri()).max(10),
    videoUrl: Joi.string().uri(),
    price: Joi.number().min(0).required(),
    mrp: Joi.number().min(0),
    variants: Joi.array().items(Joi.object({
      name: Joi.string().max(100), price: Joi.number().min(0), stock: Joi.number().integer().min(0), sku: Joi.string().max(50),
    })).max(20),
    stock: Joi.number().integer().min(0),
    lowStockThreshold: Joi.number().integer().min(0),
    isCustomOrder: Joi.boolean(),
    tags: Joi.array().items(Joi.string().max(40)).max(20),
  })),
  productController.create);
router.delete('/:id', requireAuth, requireRole('entrepreneur'), productController.remove);

module.exports = router;
