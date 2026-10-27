const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const { productDescriptionSchema, assistantSchema } = require('../validators/ai.validator');
const ctrl = require('../controllers/ai.controller');

// AI calls cost money: limit per signed-in user (in-memory per instance; use a shared store behind several instances).
const aiLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 30, standardHeaders: true,
  keyGenerator: (req) => `u:${req.user.id}`, // requireAuth runs first, so req.user always exists
  message: { success: false, error: { message: 'Too many AI requests. Please try again later.' } },
});

router.post('/product-description', requireAuth, requireRole('entrepreneur'), aiLimiter,
  validate(productDescriptionSchema), ctrl.productDescription);

// Customer help assistant (any signed-in member). Real AI only: with no provider configured it answers 503, never a canned reply.
router.post('/assistant', requireAuth, aiLimiter, validate(assistantSchema), ctrl.assistant);

module.exports = router;
