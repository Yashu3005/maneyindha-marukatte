const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const adminController = require('../controllers/admin.controller');

router.use(requireAuth, requireRole('admin', 'super_admin'));

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

module.exports = router;
