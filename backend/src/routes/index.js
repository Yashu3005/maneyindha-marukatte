const router = require('express').Router();

router.use('/auth', require('./auth.routes'));
router.use('/businesses', require('./business.routes'));
router.use('/products', require('./product.routes'));
router.use('/orders', require('./order.routes'));
router.use('/cart', require('./cart.routes'));
router.use('/reviews', require('./review.routes'));
router.use('/wishlist', require('./wishlist.routes'));
router.use('/admin', require('./admin.routes'));
// Phase additions: /payments /community /delivery ...

module.exports = router;
