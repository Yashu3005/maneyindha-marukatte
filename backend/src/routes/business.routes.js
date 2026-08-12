const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const businessController = require('../controllers/business.controller');

router.get('/nearby', businessController.nearby);          // ?lat=&lng=&radiusKm=
router.get('/:id', businessController.getById);
router.post('/', requireAuth, requireRole('entrepreneur'), businessController.create);

module.exports = router;
