const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/rewards.controller');

router.get('/me', requireAuth, ctrl.mine);
// Badges belong to the entrepreneurs.
router.get('/seller', requireAuth, requireRole('entrepreneur'), ctrl.seller);

module.exports = router;
