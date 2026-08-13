const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const Order = require('../models/Order');
const AppError = require('../utils/AppError');
const { ok } = require('../utils/apiResponse');

router.use(requireAuth, requireRole('delivery_partner'));

// Ready orders with no partner yet — the pickup pool.
router.get('/available', async (req, res, next) => {
  try {
    const items = await Order.find({ status: 'ready', deliveryPartner: null, isSelfPickup: false })
      .sort('createdAt').limit(30)
      .populate('business', 'name address');
    ok(res, items);
  } catch (e) { next(e); }
});

router.post('/accept',
  validate(Joi.object({ orderId: Joi.string().hex().length(24).required() })),
  async (req, res, next) => {
    try {
      const order = await Order.findOneAndUpdate(
        { _id: req.body.orderId, status: 'ready', deliveryPartner: null },
        {
          deliveryPartner: req.user.id,
          status: 'assigned',
          $push: { statusHistory: { status: 'assigned', at: new Date(), by: req.user.id } },
        },
        { new: true }
      );
      if (!order) throw new AppError('Order no longer available', 409);
      ok(res, order);
    } catch (e) { next(e); }
  });

module.exports = router;
