const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const usersController = require('../controllers/users.controller');

router.use(requireAuth);
router.get('/me', usersController.me);
router.patch('/me', usersController.updateMe);
router.post('/me/role', usersController.switchRole);
router.post('/me/credentials', usersController.setCredentials);
router.post('/me/security-questions', usersController.setSecurityQuestions);

module.exports = router;
