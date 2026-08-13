const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const paymentService = require('../services/payment.service');
const { ok } = require('../utils/apiResponse');

router.use(requireAuth, requireRole('customer', 'entrepreneur'));

router.post('/link',
  validate(Joi.object({
    orderId: Joi.string().hex().length(24).required(),
    returnUrl: Joi.string().uri(),
  })),
  async (req, res, next) => {
    try { ok(res, await paymentService.createPaymentLink(req.user.id, req.body.orderId, req.body.returnUrl)); }
    catch (e) { next(e); }
  });

router.post('/verify',
  validate(Joi.object({ orderId: Joi.string().hex().length(24).required() })),
  async (req, res, next) => {
    try { ok(res, await paymentService.verifyPayment(req.user.id, req.body.orderId)); }
    catch (e) { next(e); }
  });

module.exports = router;
