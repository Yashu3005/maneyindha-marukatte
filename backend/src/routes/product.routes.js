const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole, optionalAuth } = require('../middleware/auth');
const validate = require('../middleware/validate');
const productController = require('../controllers/product.controller');
const multer = require('multer');
const rateLimit = require('express-rate-limit');
const AppError = require('../utils/AppError');
const { ok } = require('../utils/apiResponse');
const photoService = require('../services/productPhoto.service');

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: photoService.MAX_BYTES, files: 1, fields: 0 } });
const photoLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 60, standardHeaders: true });
const receivePhoto = (req, res, next) => upload.single('photo')(req, res, (err) => {
  if (!err) return next();
  if (err.code === 'LIMIT_FILE_SIZE') return next(new AppError('Image must be 3 MB or smaller', 413));
  return next(new AppError('Invalid upload', 400));
});

const objectId = Joi.string().hex().length(24);

router.get('/', optionalAuth, productController.list);      // ?q=&category=&business=&page=&limit=&sort=
router.get('/:id', optionalAuth, productController.getById);
// Upload a product photo from the seller's gallery; the returned URL is then sent as images[] when adding the product.
router.post('/photo', requireAuth, requireRole('entrepreneur'), photoLimiter, receivePhoto, async (req, res, next) => {
  try { ok(res, { url: await photoService.uploadProductPhoto(req.user.id, req.file) }); } catch (e) { next(e); }
});
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
