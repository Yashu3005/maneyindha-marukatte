const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const { requireAuth } = require('../middleware/auth');
const paymentController = require('../controllers/payment.controller');

const paymentLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
});

router.post('/razorpay/create-order', requireAuth, paymentLimiter, paymentController.createOrder);
router.post('/razorpay/verify', requireAuth, paymentLimiter, paymentController.verify);
router.post('/webhook', paymentController.webhook);
router.get('/transactions', requireAuth, paymentController.myTransactions);

module.exports = router;
