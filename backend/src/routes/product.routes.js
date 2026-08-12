const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const productController = require('../controllers/product.controller');

router.get('/', productController.list);                    // ?q=&category=&page=&limit=&sort=
router.get('/:id', productController.getById);
router.post('/', requireAuth, requireRole('entrepreneur'), productController.create);
router.delete('/:id', requireAuth, requireRole('entrepreneur'), productController.remove);

module.exports = router;
