const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const adminController = require('../controllers/admin.controller');

router.use(requireAuth, requireRole('admin', 'super_admin'));

router.get('/verifications', adminController.listVerifications); // ?status=pending|in_review|approved|rejected
router.post('/verifications/:businessId',
  validate(Joi.object({
    action: Joi.string().valid('approve', 'reject', 'request_info').required(),
    reason: Joi.string().max(500),
  })),
  adminController.reviewBusiness);

module.exports = router;
