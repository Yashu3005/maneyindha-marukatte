const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole, optionalAuth } = require('../middleware/auth');
const validate = require('../middleware/validate');
const businessController = require('../controllers/business.controller');

const geo = require('../validators/geo.validator');

const optStr = (max) => Joi.string().trim().max(max).allow('');

router.get('/', businessController.list);
router.get('/mine', requireAuth, requireRole('entrepreneur'), businessController.mine);
router.get('/nearby', businessController.nearby);          // ?lat=&lng=&radiusKm=&sort=&category=&minRating=&openNow=&hasVideo=&q=
// Owner-only: set the shop's exact location (from the device or typed in by hand).
router.patch('/:id/location', requireAuth, requireRole('entrepreneur'), validate(geo.setLocationSchema), businessController.setLocation);
router.get('/:id/rating-summary', businessController.ratingSummary);
router.get('/:id', optionalAuth, businessController.getById);
router.post('/', requireAuth, requireRole('entrepreneur'),
  validate(Joi.object({
    name: Joi.string().trim().min(2).max(120).required(),
    description: optStr(2000),
    category: Joi.string().trim().max(100),          // ObjectId or category name
    logoUrl: Joi.string().uri(),
    bannerUrl: Joi.string().uri(),
    gallery: Joi.array().items(Joi.string().uri()).max(20),
    location: geo.point,
    locationSource: Joi.string().valid('device', 'manual'),
    address: Joi.object({ line1: optStr(200), city: optStr(100), state: optStr(100), pincode: optStr(10) }),
    workingHours: Joi.array().items(Joi.object({
      day: Joi.number().integer().min(0).max(6), open: optStr(10), close: optStr(10), closed: Joi.boolean(),
    })).max(7),
    gstNumber: optStr(20),
    yearsOfExperience: optStr(30),
  })),
  businessController.create);

// Verification documents: private uploads, then an explicit submit.
const multer = require('multer');
const rateLimit = require('express-rate-limit');
const AppError = require('../utils/AppError');
const docs = require('../services/verificationDoc.service');
const docUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: docs.MAX_BYTES, files: 1, fields: 4 } });
const docLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 40, standardHeaders: true });
const receiveDoc = (req, res, next) => docUpload.single('file')(req, res, (err) => {
  if (!err) return next();
  if (err.code === 'LIMIT_FILE_SIZE') return next(new AppError('File must be 5 MB or smaller', 413));
  return next(new AppError('Invalid upload', 400));
});
const ownerOnly = [requireAuth, requireRole('entrepreneur')];

router.get('/:id/documents', ...ownerOnly, businessController.listDocuments);
router.post('/:id/documents', ...ownerOnly, docLimiter, receiveDoc,
  validate(Joi.object({
    type: Joi.string().valid(...docs.DOC_TYPES).required(),
    identityType: Joi.string().valid(...docs.IDENTITY_TYPES),
  })),
  businessController.addDocument);
router.delete('/:id/documents/:docId', ...ownerOnly, businessController.removeDocument);
// Entrepreneur submits → status: in_review (needs ID proof + business proof uploaded)
router.post('/:id/verification-documents', ...ownerOnly, validate(Joi.object({})), businessController.uploadDocs);


// Promo video: the browser uploads straight to Cloudinary with a signature from here, then reports it for checking.
router.post('/:id/promo-video/signature', ...ownerOnly, rateLimit({ windowMs: 60 * 60 * 1000, max: 20, standardHeaders: true }), businessController.promoSignature);
router.post('/:id/promo-video', ...ownerOnly,
  validate(Joi.object({ publicId: Joi.string().max(120).required(), title: optStr(80), caption: optStr(240) })),
  businessController.promoAttach);
router.delete('/:id/promo-video', ...ownerOnly, businessController.promoRemove);

module.exports = router;
