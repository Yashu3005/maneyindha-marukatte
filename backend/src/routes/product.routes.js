const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const productController = require('../controllers/product.controller');

router.get('/', productController.list);
router.get('/:id', productController.getById);

router.post('/', requireAuth, requireRole('entrepreneur', 'admin'), productController.create);
router.patch('/:id', requireAuth, requireRole('entrepreneur', 'admin'), productController.update);
router.patch('/:id/stock', requireAuth, requireRole('entrepreneur', 'admin'), productController.updateStock);
router.delete('/:id', requireAuth, requireRole('entrepreneur', 'admin'), productController.remove);

router.post('/:id/report', requireAuth, productController.report);

// AI helpers
router.post('/ai/improve-title', requireAuth, productController.aiImproveTitle);
router.post('/ai/suggest-price', requireAuth, productController.aiSuggestPrice);
router.post('/ai/generate-description', requireAuth, productController.aiGenerateDescription);

module.exports = router;
