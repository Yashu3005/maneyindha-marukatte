const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const businessController = require('../controllers/business.controller');

router.get('/nearby', businessController.nearby);          // ?lat=&lng=&radiusKm=
router.get('/:id', businessController.getById);
router.post('/', requireAuth, requireRole('entrepreneur'), businessController.create);

// Verification documents (entrepreneur submits → status: in_review)
router.post('/:id/verification-documents',
  requireAuth, requireRole('entrepreneur'),
  validate(Joi.object({
    documents: Joi.array().items(Joi.object({
      type: Joi.string().valid('id_proof', 'address_proof', 'gst', 'fssai', 'other').required(),
      url: Joi.string().uri().required(),
    })).min(1).required(),
  })),
  businessController.uploadDocs);

module.exports = router;
