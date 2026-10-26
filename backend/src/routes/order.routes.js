const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const orderController = require('../controllers/order.controller');

router.post('/', requireAuth, requireRole('customer', 'entrepreneur'), orderController.create);
router.get('/mine', requireAuth, orderController.myOrders);
router.patch('/:id/status', requireAuth, orderController.updateStatus); // transition-validated in service

module.exports = router;
