const router = require('express').Router();

router.use('/auth', require('./auth.routes'));
router.use('/businesses', require('./business.routes'));
router.use('/products', require('./product.routes'));
router.use('/orders', require('./order.routes'));
// Phase additions: /payments /reviews /cart /community /admin /delivery ...

module.exports = router;
