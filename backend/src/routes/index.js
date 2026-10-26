const router = require('express').Router();

router.use('/auth', require('./auth.routes'));
router.use('/users', require('./users.routes'));
router.use('/businesses', require('./business.routes'));
router.use('/products', require('./product.routes'));
router.use('/orders', require('./order.routes'));
router.use('/cart', require('./cart.routes'));
router.use('/reviews', require('./review.routes'));
router.use('/wishlist', require('./wishlist.routes'));
router.use('/admin', require('./admin.routes'));
router.use('/images', require('./images.routes'));

module.exports = router;
