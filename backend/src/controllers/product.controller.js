const Product = require('../models/Product');
const Business = require('../models/Business');
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');

exports.list = async (req, res, next) => {
  try {
    const { q, category, business, page = 1, limit = 20, sort = '-createdAt' } = req.query;
    const filter = { isActive: true };
    if (q) filter.$text = { $search: q };
    if (category) filter.category = category;
    if (business) {
      // Specific shop requested (e.g. an entrepreneur viewing their own).
      filter.business = business;
    } else {
      // Public catalog: only products from approved, active shops.
      const approved = await Business
        .find({ 'verification.status': 'approved', isActive: true })
        .select('_id');
      filter.business = { $in: approved.map((b) => b._id) };
    }
    const [items, total] = await Promise.all([
      Product.find(filter).sort(sort).skip((page - 1) * limit).limit(Number(limit)),
      Product.countDocuments(filter),
    ]);
    ok(res, items, { page: Number(page), limit: Number(limit), total });
  } catch (e) { next(e); }
};

exports.getById = async (req, res, next) => {
  try {
    const product = await Product.findById(req.params.id).populate('business', 'name slug rating');
    if (!product || !product.isActive) throw new AppError('Product not found', 404);
    ok(res, product);
  } catch (e) { next(e); }
};

exports.create = async (req, res, next) => {
  try {
    // Entrepreneurs may only add products to their own business.
    const business = await Business.findOne({ _id: req.body.business, owner: req.user.id });
    if (!business) throw new AppError('Business not found or not owned by you', 403);
    const product = await Product.create(req.body);
    ok(res, product, undefined, 201);
  } catch (e) { next(e); }
};

exports.remove = async (req, res, next) => {
  try {
    const product = await Product.findById(req.params.id);
    if (!product) throw new AppError('Product not found', 404);
    const owned = await Business.findOne({ _id: product.business, owner: req.user.id });
    if (!owned) throw new AppError('You can only delete your own products', 403);
    product.isActive = false;
    product.deletedAt = new Date();
    await product.save();
    ok(res, { deleted: true });
  } catch (e) { next(e); }
};
