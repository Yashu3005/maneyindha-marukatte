const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const multer = require('multer');
const rateLimit = require('express-rate-limit');
const AppError = require('../utils/AppError');
const { requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const { updateMeSchema } = require('../validators/geo.validator');
const usersController = require('../controllers/users.controller');

// Memory storage + hard size cap: nothing touches disk, and oversized bodies are cut off while streaming.
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 2 * 1024 * 1024, files: 1, fields: 0 } });
const avatarLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 20, standardHeaders: true });
const receiveAvatar = (req, res, next) => upload.single('avatar')(req, res, (err) => {
  if (!err) return next();
  if (err.code === 'LIMIT_FILE_SIZE') return next(new AppError('Image must be 2 MB or smaller', 413));
  return next(new AppError('Invalid upload', 400));
});

router.use(requireAuth);
router.get('/me', usersController.me);
router.patch('/me', validate(updateMeSchema), usersController.updateMe);
// Profile photos are optional and offered to women entrepreneurs; customers use the default avatar.
router.post('/me/avatar', requireRole('entrepreneur'), avatarLimiter, receiveAvatar, usersController.uploadAvatar);
router.delete('/me/avatar', requireRole('entrepreneur', 'customer'), usersController.deleteAvatar);
router.post('/me/role', usersController.switchRole);
router.post('/me/credentials', usersController.setCredentials);
router.post('/me/security-questions', usersController.setSecurityQuestions);

module.exports = router;
