const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const Notification = require('../models/Notification');
const { ok } = require('../utils/apiResponse');

router.use(requireAuth);

router.get('/', async (req, res, next) => {
  try {
    const items = await Notification.find({ user: req.user.id })
      .sort('-createdAt').limit(50);
    const unread = await Notification.countDocuments({ user: req.user.id, isRead: false });
    ok(res, items, { unread });
  } catch (e) { next(e); }
});

router.patch('/read-all', async (req, res, next) => {
  try {
    await Notification.updateMany({ user: req.user.id, isRead: false }, { isRead: true });
    ok(res, { done: true });
  } catch (e) { next(e); }
});

module.exports = router;
