const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const { createOrderSchema, updateStatusSchema } = require('../validators/order.validator');
const orderController = require('../controllers/order.controller');

router.post('/', requireAuth, requireRole('customer', 'entrepreneur'), validate(createOrderSchema), orderController.create);
router.get('/mine', requireAuth, orderController.myOrders);
router.get('/received', requireAuth, requireRole('entrepreneur'), orderController.received);
// Only order participants (customer, shop owner, assigned partner) or admins may
// change status; legality of the transition is enforced in the service.
router.patch('/:id/status', requireAuth, validate(updateStatusSchema), orderController.updateStatus);

module.exports = router;
