const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/rewards.controller');

router.get('/me', requireAuth, ctrl.mine);

module.exports = router;
