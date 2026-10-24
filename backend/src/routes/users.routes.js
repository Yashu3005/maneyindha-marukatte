const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const usersController = require('../controllers/users.controller');

router.use(requireAuth);
router.get('/me', usersController.me);
router.patch('/me', usersController.updateMe);
router.post('/me/role', usersController.switchRole);
router.post('/me/credentials', usersController.setCredentials);
router.post('/me/security-questions', usersController.setSecurityQuestions);

// Address Book
router.get('/me/addresses', usersController.getAddresses);
router.post('/me/addresses', usersController.addAddress);
router.patch('/me/addresses/:addressId', usersController.updateAddress);
router.delete('/me/addresses/:addressId', usersController.deleteAddress);
router.post('/me/addresses/:addressId/default', usersController.setDefaultAddress);

module.exports = router;
