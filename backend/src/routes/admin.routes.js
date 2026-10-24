const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const adminController = require('../controllers/admin.controller');

router.use(requireAuth, requireRole('admin', 'super_admin'));

// Stats & Dashboard
router.get('/stats', adminController.getStats);

// Verifications
router.get('/verifications', adminController.listVerifications);
router.post(
  '/verifications/:businessId',
  validate(
    Joi.object({
      action: Joi.string().valid('approve', 'reject', 'request_info').required(),
      reason: Joi.string().max(500).allow(''),
    })
  ),
  adminController.reviewBusiness
);

// Entrepreneurs & Badges
router.get('/entrepreneurs', adminController.listEntrepreneurs);
router.post('/entrepreneurs/:businessId/badge', adminController.assignBadge);

// Products & Moderation
router.get('/products', adminController.listProducts);
router.post('/products/:productId/moderate', adminController.moderateProduct);

// Categories
router.get('/categories', adminController.listCategories);
router.post('/categories', adminController.createCategory);
router.patch('/categories/:id', adminController.updateCategory);

// AI Trends & Activity Logs
router.get('/ai-trend-analysis', adminController.getTrendAnalysis);
router.get('/activity-logs', adminController.getActivityLogs);

module.exports = router;
