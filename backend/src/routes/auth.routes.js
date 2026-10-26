const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const validate = require('../middleware/validate');
const {
  registerSchema,
  loginSchema,
  sendOtpSchema,
  verifyOtpSchema,
} = require('../validators/auth.validator');
const authController = require('../controllers/auth.controller');

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
});

// Stricter rate limiter on OTP requests to guard against abuse and spam
const otpLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 15,
  message: {
    success: false,
    message: 'Too many verification code requests from this IP. Please wait 15 minutes.',
  },
  standardHeaders: true,
  legacyHeaders: false,
});

router.post('/register', authLimiter, validate(registerSchema), authController.register);
router.post('/login', authLimiter, validate(loginSchema), authController.login);
router.post('/refresh', authLimiter, authController.refresh);
router.post('/firebase-exchange', authLimiter, authController.firebaseExchange);
router.post('/otp/send', otpLimiter, validate(sendOtpSchema), authController.sendOtp);
router.post('/otp/verify', otpLimiter, validate(verifyOtpSchema), authController.verifyOtp);

module.exports = router;
