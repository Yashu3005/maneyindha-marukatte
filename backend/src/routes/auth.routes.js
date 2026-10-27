const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const validate = require('../middleware/validate');
const { registerSchema, loginSchema, sendOtpSchema, verifyOtpSchema, adminLoginSchema } = require('../validators/auth.validator');
const { requireAuth } = require('../middleware/auth');
const authController = require('../controllers/auth.controller');

const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 60, standardHeaders: true });

router.post('/register', authLimiter, validate(registerSchema), authController.register);
router.post('/login', authLimiter, validate(loginSchema), authController.login);
router.post('/refresh', authLimiter, authController.refresh);
router.post('/firebase-exchange', authLimiter, authController.firebaseExchange);
// Sending triggers a real email: keep the per-IP budget tight (the per-address
// cooldown and attempt limits live in otp.service).
const otpSendLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 10, standardHeaders: true,
  message: { success: false, error: { message: 'Too many code requests. Try again later.', code: 'RATE_LIMITED' } } });
router.post('/otp/send', otpSendLimiter, validate(sendOtpSchema), authController.sendOtp);
router.post('/otp/verify', authLimiter, validate(verifyOtpSchema), authController.verifyOtp);
// The single administrator signs in here (credentials come from server configuration). Tight limit: it is a password endpoint.
const adminLoginLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 10, standardHeaders: true,
  message: { success: false, error: { message: 'Too many sign-in attempts. Try again later.', code: 'RATE_LIMITED' } } });
router.post('/admin/login', adminLoginLimiter, validate(adminLoginSchema), authController.adminLogin);
router.post('/logout', authController.logout);
router.post('/logout-all', requireAuth, authController.logoutAll);

module.exports = router;
