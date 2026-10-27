const mongoose = require('mongoose');
const Review = require('../models/Review');
const Order = require('../models/Order');
const Product = require('../models/Product');
const Business = require('../models/Business');
const AppError = require('../utils/AppError');

exports.createReview = async (customerId, { productId, orderId, rating, comment, images }) => {
  const product = await Product.findOne({ _id: productId, isActive: true });
  if (!product) throw new AppError('Product not found', 404);

  // Ratings are honest only if they come from real buyers: the order must be DELIVERED, belong to this
  // customer, and contain this product. There is no way to rate something you have not received.
  if (!orderId) throw new AppError('You can rate a product after your order has been delivered', 422, 'ORDER_REQUIRED');
  const ownShop = await Business.exists({ _id: product.business, owner: customerId });
  if (ownShop) throw new AppError('You cannot rate your own products', 403);
  const order = await Order.findOne({
    _id: orderId, customer: customerId, status: 'delivered', 'items.product': productId,
  });
  if (!order) throw new AppError('No delivered order found for this product', 422);
  const isVerifiedPurchase = true;

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

/** Items from this customer's delivered orders that they have not rated yet (newest first). */
exports.toRate = async (customerId) => {
  const orders = await Order.find({ customer: customerId, status: 'delivered' })
    .sort('-createdAt').limit(20).populate('business', 'name');
  if (!orders.length) return [];
  const done = await Review.find({ customer: customerId, order: { $in: orders.map((o) => o._id) } }).select('order product');
  const rated = new Set(done.map((r) => `${r.order}:${r.product}`));
  const out = [];
  for (const o of orders) {
    const items = o.items.filter((i) => !rated.has(`${o._id}:${i.product}`));
    if (items.length) {
      out.push({
        orderId: o._id, orderNumber: o.orderNumber, deliveredAt: o.updatedAt,
        business: { id: o.business?._id, name: o.business?.name },
        items: items.map((i) => ({ productId: i.product, name: i.name })),
      });
    }
  }
  return out;
};

/** Average, count and 1-5 star distribution for a shop, from its real reviews. */
exports.businessSummary = async (businessId) => {
  const rows = await Review.aggregate([
    { $match: { business: new mongoose.Types.ObjectId(businessId), deletedAt: null } },
    { $group: { _id: '$rating', n: { $sum: 1 } } },
  ]);
  const distribution = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
  let count = 0; let sum = 0;
  for (const r of rows) { distribution[r._id] = r.n; count += r.n; sum += r._id * r.n; }
  return { average: count ? Math.round((sum / count) * 10) / 10 : 0, count, distribution };
};
