const Product = require('../models/Product');
const Business = require('../models/Business');
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');
const { parsePage, isObjectId } = require('../utils/pagination');

const ADMIN_ROLES = ['admin', 'super_admin'];
const SORTS = ['-createdAt', 'createdAt', 'price', '-price', '-rating.avg', 'name'];
const CREATE_FIELDS = ['business', 'name', 'description', 'category', 'images', 'videoUrl', 'price', 'mrp',
  'variants', 'stock', 'lowStockThreshold', 'isCustomOrder', 'tags'];

const canSeeUnapproved = (user, business) =>
  !!user && (ADMIN_ROLES.includes(user.role) || String(business.owner) === String(user.id));

exports.list = async (req, res, next) => {
  try {
    const { q, category, business, sort } = req.query;
    const { page, limit, skip } = parsePage(req.query);
    const filter = { isActive: true };
    if (q) filter.$text = { $search: String(q).slice(0, 100) };
    if (category) {
      if (!isObjectId(category)) throw new AppError('Invalid category', 422);
      filter.category = category;
    }
    if (business) {
      if (!isObjectId(business)) throw new AppError('Invalid business', 422);
      // A specific shop's catalogue is public only once the shop is approved; its
      // owner (and admins) may always see it — the seller dashboard relies on this.
      const shop = await Business.findOne({ _id: business, isActive: true }).select('owner verification.status');
      const visible = shop && (shop.verification?.status === 'approved' || canSeeUnapproved(req.user, shop));
      if (!visible) return ok(res, [], { page, limit, total: 0 });
      filter.business = business;
    } else {
      // Public catalog: only products from approved, active shops.
      const approved = await Business
        .find({ 'verification.status': 'approved', isActive: true })
        .select('_id');
      filter.business = { $in: approved.map((b) => b._id) };
    }
    const sortBy = SORTS.includes(sort) ? sort : '-createdAt';
    const [items, total] = await Promise.all([
      Product.find(filter).sort(sortBy).skip(skip).limit(limit),
      Product.countDocuments(filter),
    ]);
    ok(res, items, { page, limit, total });
  } catch (e) { next(e); }
};

exports.getById = async (req, res, next) => {
  try {
    const product = await Product.findById(req.params.id)
      .populate('business', 'name slug rating owner isActive verification.status');
    if (!product || !product.isActive) throw new AppError('Product not found', 404);
    const shop = product.business;
    if (!shop || !shop.isActive) throw new AppError('Product not found', 404);
    if (shop.verification?.status !== 'approved' && !canSeeUnapproved(req.user, shop)) {
      throw new AppError('Product not found', 404);
    }
    // Keep the public shape ({_id,name,slug,rating}) — no owner/verification internals.
    const out = product.toObject();
    out.business = { _id: shop._id, name: shop.name, slug: shop.slug, rating: shop.rating };
    ok(res, out);
  } catch (e) { next(e); }
};

exports.create = async (req, res, next) => {
  try {
    // Entrepreneurs may only add products to their own business.
    const business = await Business.findOne({ _id: req.body.business, owner: req.user.id });
    if (!business) throw new AppError('Business not found or not owned by you', 403);
    // Whitelist fields — client must not set rating, isActive, deletedAt, etc.
    const data = {};
    for (const key of CREATE_FIELDS) if (req.body[key] !== undefined) data[key] = req.body[key];
    const product = await Product.create(data);
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
