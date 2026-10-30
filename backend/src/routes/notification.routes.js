const router = require('express').Router();
const Joi = require('joi');
const { requireAuth } = require('../middleware/auth');
const validate = require('../middleware/validate');
const { ok } = require('../utils/apiResponse');
const notifications = require('../services/notification.service');

router.get('/', requireAuth, async (req, res, next) => {
  try { res.set('Cache-Control', 'no-store'); ok(res, await notifications.listFor(req.user.id)); } catch (e) { next(e); }
});
// Body { ids?: [...] }; no ids = mark everything read.
router.post('/read', requireAuth,
  validate(Joi.object({ ids: Joi.array().items(Joi.string().hex().length(24)).max(100) })),
  async (req, res, next) => {
    try { ok(res, await notifications.markRead(req.user.id, req.body.ids)); } catch (e) { next(e); }
  });

module.exports = router;
