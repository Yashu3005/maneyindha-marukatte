const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const { requireAuth } = require('../middleware/auth');
const validate = require('../middleware/validate');
const { createRazorpayOrderSchema, verifyPaymentSchema } = require('../validators/payment.validator');
const ctrl = require('../controllers/payment.controller');

// The webhook route is mounted in app.js (it needs the raw body, before express.json).
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 60, standardHeaders: true });

router.post('/razorpay/order', requireAuth, limiter, validate(createRazorpayOrderSchema), ctrl.createOrder);
router.post('/razorpay/verify', requireAuth, limiter, validate(verifyPaymentSchema), ctrl.verify);
router.get('/status/:orderId', requireAuth, ctrl.status);

module.exports = router;
