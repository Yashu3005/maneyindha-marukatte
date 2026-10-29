const router = require('express').Router();
const Joi = require('joi');
const { requireAdmin } = require('../middleware/auth');
const validate = require('../middleware/validate');
const adminController = require('../controllers/admin.controller');

// Only the one configured administrator account gets in (see middleware/auth.requireAdmin).
router.use(...requireAdmin);

router.get('/stats', adminController.stats);

router.get('/users',
  validate(Joi.object({
    role: Joi.string().valid('customer', 'entrepreneur', 'delivery_partner'),
    q: Joi.string().trim().max(60).allow(''),
    page: Joi.number().integer().min(1),
    limit: Joi.number().integer().min(1).max(100),
  }), 'query'),
  adminController.listUsers);
router.patch('/users/:id/status',
  validate(Joi.object({ isActive: Joi.boolean().required() })),
  adminController.setUserStatus);

router.get('/verifications',
  validate(Joi.object({
    status: Joi.string().valid('pending', 'in_review', 'approved', 'rejected'),
    page: Joi.number().integer().min(1),
    limit: Joi.number().integer().min(1).max(100),
  }), 'query'),
  adminController.listVerifications); // ?status=pending|in_review|approved|rejected
router.post('/verifications/:businessId',
  validate(Joi.object({
    action: Joi.string().valid('approve', 'reject', 'request_info').required(),
    reason: Joi.string().max(500),
  })),
  adminController.reviewBusiness);

// Short-lived link to one verification document (admins only; documents are never public).
router.get('/verifications/:businessId/documents/:docId/link', adminController.documentLink);

// Shop videos wait here until approved; only approved ones reach the customers' home screen.
router.get('/promo-videos',
  validate(Joi.object({ status: Joi.string().valid('pending', 'approved', 'rejected') }), 'query'),
  adminController.listPromoVideos);
router.post('/businesses/:businessId/promo-video/review',
  validate(Joi.object({ action: Joi.string().valid('approve', 'reject').required(), reason: Joi.string().trim().max(300).allow('') })),
  adminController.reviewPromoVideo);

// Take down a shop's promo video (e.g. unsuitable content). The owner can upload a new one.
router.delete('/businesses/:businessId/promo-video', adminController.removePromoVideo);

module.exports = router;
