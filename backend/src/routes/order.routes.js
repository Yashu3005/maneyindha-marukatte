const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const orderController = require('../controllers/order.controller');

router.use(requireAuth);

router.post('/', requireRole('customer', 'entrepreneur'), orderController.create);
router.get('/mine', orderController.myOrders);
router.get('/after-sales/entrepreneur', requireRole('entrepreneur', 'admin'), orderController.afterSalesList);
router.get('/:id', orderController.getById);
router.patch('/:id/status', orderController.updateStatus);
router.post('/:id/cancel', orderController.cancel);

// After-Sales workflows
router.post('/:id/after-sales', orderController.requestAfterSales);
router.post('/:id/after-sales/decide', requireRole('entrepreneur', 'admin'), orderController.decideAfterSales);
router.post('/:id/return/start', orderController.startReturn);
router.post('/:id/return/confirm', requireRole('entrepreneur', 'admin'), orderController.confirmReturn);

module.exports = router;
