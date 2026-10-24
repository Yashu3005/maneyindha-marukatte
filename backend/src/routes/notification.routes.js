const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const notificationController = require('../controllers/notification.controller');

router.use(requireAuth);

router.get('/', notificationController.list);
router.patch('/:id/read', notificationController.markRead);
router.delete('/:id', notificationController.remove);
router.delete('/', notificationController.clearAll);

module.exports = router;
