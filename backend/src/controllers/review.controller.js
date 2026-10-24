const reviewService = require('../services/review.service');
const { ok } = require('../utils/apiResponse');

exports.create = async (req, res, next) => {
  try { ok(res, await reviewService.createReview(req.user.id, req.body), undefined, 201); } catch (e) { next(e); }
};
exports.listForProduct = async (req, res, next) => {
  try {
    const { items, meta } = await reviewService.listForProduct(req.params.productId, req.query);
    ok(res, items, meta);
  } catch (e) { next(e); }
};
exports.reply = async (req, res, next) => {
  try { ok(res, await reviewService.reply(req.user.id, req.params.id, req.body.text)); } catch (e) { next(e); }
};

exports.listForBusiness = async (req, res, next) => {
  try {
    const Review = require('../models/Review');
    const items = await Review.find({ business: req.params.businessId, deletedAt: null })
      .sort('-createdAt').limit(50).populate('customer', 'name avatarUrl');
    ok(res, items);
  } catch (e) { next(e); }
};
