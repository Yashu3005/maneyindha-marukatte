const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole, optionalAuth } = require('../middleware/auth');
const validate = require('../middleware/validate');
const businessController = require('../controllers/business.controller');

const optStr = (max) => Joi.string().trim().max(max).allow('');

router.get('/', businessController.list);
router.get('/mine', requireAuth, requireRole('entrepreneur'), businessController.mine);
router.get('/nearby', businessController.nearby);          // ?lat=&lng=&radiusKm=
router.get('/:id', optionalAuth, businessController.getById);
router.post('/', requireAuth, requireRole('entrepreneur'),
  validate(Joi.object({
    name: Joi.string().trim().min(2).max(120).required(),
    description: optStr(2000),
    category: Joi.string().trim().max(100),          // ObjectId or category name
    logoUrl: Joi.string().uri(),
    bannerUrl: Joi.string().uri(),
    gallery: Joi.array().items(Joi.string().uri()).max(20),
    location: Joi.object({
      type: Joi.string().valid('Point'),
      coordinates: Joi.array().ordered(
        Joi.number().min(-180).max(180), Joi.number().min(-90).max(90)).length(2).required(),
    }),
    address: Joi.object({ line1: optStr(200), city: optStr(100), state: optStr(100), pincode: optStr(10) }),
    workingHours: Joi.array().items(Joi.object({
      day: Joi.number().integer().min(0).max(6), open: optStr(10), close: optStr(10), closed: Joi.boolean(),
    })).max(7),
    gstNumber: optStr(20),
    yearsOfExperience: optStr(30),
  })),
  businessController.create);

// Verification documents (entrepreneur submits → status: in_review)
router.post('/:id/verification-documents',
  requireAuth, requireRole('entrepreneur'),
  validate(Joi.object({
    documents: Joi.array().items(Joi.object({
      type: Joi.string().valid('id_proof', 'address_proof', 'business_proof', 'profile_photo', 'gst', 'fssai', 'other').required(),
      identityType: Joi.string().valid('Aadhaar', 'Voter ID', 'Driving License', 'Passport'),
      url: Joi.string().uri().required(),
    })).min(1).required(),
  })),
  businessController.uploadDocs);

module.exports = router;
