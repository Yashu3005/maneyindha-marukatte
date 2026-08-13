const mongoose = require('mongoose');
const Review = require('../models/Review');
const Order = require('../models/Order');
const Product = require('../models/Product');
const Business = require('../models/Business');
const AppError = require('../utils/AppError');

exports.createReview = async (customerId, { productId, orderId, rating, comment, images }) => {
  const product = await Product.findOne({ _id: productId, isActive: true });
  if (!product) throw new AppError('Product not found', 404);

  // Verified purchase check: order must be delivered, belong to this customer,
  // and contain this product.
  let isVerifiedPurchase = false;
  if (orderId) {
    const order = await Order.findOne({
      _id: orderId, customer: customerId, status: 'delivered', 'items.product': productId,
    });
    if (!order) throw new AppError('No delivered order found for this product', 422);
    isVerifiedPurchase = true;
  }

  const review = await Review.create({
    customer: customerId,
    business: product.business,
    product: productId,
    order: orderId,
    rating, comment, images,
    isVerifiedPurchase,
  }).catch((e) => {
    if (e.code === 11000) throw new AppError('You have already reviewed this product for this order', 409);
    throw e;
  });

  await Promise.all([refreshProductRating(productId), refreshBusinessRating(product.business)]);
  return review;
};

exports.listForProduct = async (productId, { page = 1, limit = 10 }) => {
  const filter = { product: productId, deletedAt: null };
  const [items, total] = await Promise.all([
    Review.find(filter).sort('-createdAt').skip((page - 1) * limit).limit(Number(limit))
      .populate('customer', 'name avatarUrl'),
    Review.countDocuments(filter),
  ]);
  return { items, meta: { page: Number(page), limit: Number(limit), total } };
};

exports.reply = async (entrepreneurId, reviewId, text) => {
  const review = await Review.findById(reviewId);
  if (!review) throw new AppError('Review not found', 404);

  const business = await Business.findOne({ _id: review.business, owner: entrepreneurId });
  if (!business) throw new AppError('You can only reply to reviews of your own business', 403);

  review.reply = { text, at: new Date() };
  await review.save();
  return review;
};

async function refreshProductRating(productId) {
  const [agg] = await Review.aggregate([
    { $match: { product: new mongoose.Types.ObjectId(productId), deletedAt: null } },
    { $group: { _id: null, avg: { $avg: '$rating' }, count: { $sum: 1 } } },
  ]);
  await Product.findByIdAndUpdate(productId, {
    rating: { avg: agg ? Math.round(agg.avg * 10) / 10 : 0, count: agg?.count || 0 },
  });
}

async function refreshBusinessRating(businessId) {
  const [agg] = await Review.aggregate([
    { $match: { business: new mongoose.Types.ObjectId(businessId), deletedAt: null } },
    { $group: { _id: null, avg: { $avg: '$rating' }, count: { $sum: 1 } } },
  ]);
  await Business.findByIdAndUpdate(businessId, {
    rating: { avg: agg ? Math.round(agg.avg * 10) / 10 : 0, count: agg?.count || 0 },
  });
}
