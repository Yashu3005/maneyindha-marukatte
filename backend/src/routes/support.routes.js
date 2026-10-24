const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const supportController = require('../controllers/support.controller');

router.use(requireAuth);

router.post('/', supportController.create);
router.get('/mine', supportController.myTickets);

router.get('/admin', requireRole('admin', 'super_admin'), supportController.adminList);
router.patch('/admin/:id', requireRole('admin', 'super_admin'), supportController.adminUpdate);

module.exports = router;
