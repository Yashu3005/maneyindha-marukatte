const Product = require('../models/Product');
const Business = require('../models/Business');
const Category = require('../models/Category');
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');

exports.list = async (req, res, next) => {
  try {
    const { q, category, business, page = 1, limit = 20, sort = '-createdAt' } = req.query;
    const filter = { isActive: true, 'moderation.status': { $ne: 'removed' } };

    if (q) {
      filter.$or = [
        { name: { $regex: q, $options: 'i' } },
        { description: { $regex: q, $options: 'i' } },
      ];
    }
    if (category) filter.category = category;
    if (business) {
      filter.business = business;
    } else {
      const approved = await Business.find({
        'verification.status': 'approved',
        isActive: true,
      }).select('_id');
      filter.business = { $in: approved.map((b) => b._id) };
    }

    const [items, total] = await Promise.all([
      Product.find(filter)
        .sort(sort)
        .skip((page - 1) * limit)
        .limit(Number(limit))
        .populate('business', 'name slug rating address isOpen')
        .populate('category', 'name'),
      Product.countDocuments(filter),
    ]);

    ok(res, items, { page: Number(page), limit: Number(limit), total });
  } catch (e) {
    next(e);
  }
};

exports.getById = async (req, res, next) => {
  try {
    const product = await Product.findById(req.params.id)
      .populate('business', 'name slug rating address isOpen deliveryRadius workingHours')
      .populate('category', 'name');
    if (!product || !product.isActive) throw new AppError('Product not found', 404);
    ok(res, product);
  } catch (e) {
    next(e);
  }
};

exports.create = async (req, res, next) => {
  try {
    const business = await Business.findOne({ _id: req.body.business, owner: req.user.id });
    if (!business) throw new AppError('Business not found or not owned by you', 403);

    const product = await Product.create(req.body);
    ok(res, product, undefined, 201);
  } catch (e) {
    next(e);
  }
};

exports.update = async (req, res, next) => {
  try {
    const product = await Product.findById(req.params.id);
    if (!product) throw new AppError('Product not found', 404);

    const business = await Business.findOne({ _id: product.business, owner: req.user.id });
    if (!business) throw new AppError('You can only edit your own products', 403);

    Object.assign(product, req.body);
    await product.save();
    ok(res, product);
  } catch (e) {
    next(e);
  }
};

exports.updateStock = async (req, res, next) => {
  try {
    const product = await Product.findById(req.params.id);
    if (!product) throw new AppError('Product not found', 404);

    const business = await Business.findOne({ _id: product.business, owner: req.user.id });
    if (!business) throw new AppError('You can only update stock for your own products', 403);

    const { stock, inStock } = req.body;
    if (stock !== undefined) product.stock = Math.max(0, Number(stock));
    if (inStock !== undefined && !inStock) product.stock = 0;

    await product.save();
    ok(res, product);
  } catch (e) {
    next(e);
  }
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
  } catch (e) {
    next(e);
  }
};

exports.report = async (req, res, next) => {
  try {
    const { reason, description } = req.body;
    const product = await Product.findById(req.params.id);
    if (!product) throw new AppError('Product not found', 404);

    if (!product.moderation) {
      product.moderation = { status: 'active', reportCount: 0, reports: [] };
    }
    product.moderation.reportCount = (product.moderation.reportCount || 0) + 1;
    product.moderation.status = 'reported';
    product.moderation.reports.push({
      customer: req.user.id,
      reason,
      description,
      createdAt: new Date(),
    });

    await product.save();
    ok(res, { reported: true });
  } catch (e) {
    next(e);
  }
};

// AI helpers (Rule-based / model driven)
exports.aiImproveTitle = async (req, res, next) => {
  try {
    const { title, category } = req.body;
    if (!title) throw new AppError('title is required', 422);

    const words = title.trim().split(' ').map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase());
    const enhanced = words.join(' ');
    const prefix = ['Fresh Homemade', 'Handcrafted', 'Authentic', 'Artisanal'][Math.floor(Math.random() * 4)];
    const suggested = `${prefix} ${enhanced}`;
    ok(res, { suggestedTitle: suggested });
  } catch (e) {
    next(e);
  }
};

exports.aiSuggestPrice = async (req, res, next) => {
  try {
    const { name, category } = req.body;
    // Suggest based on category benchmarks
    let benchmark = 350;
    const lower = (name || '').toLowerCase();
    if (lower.includes('cake')) benchmark = 450;
    else if (lower.includes('cupcake') || lower.includes('cookie')) benchmark = 150;
    else if (lower.includes('bag') || lower.includes('sari')) benchmark = 550;
    else if (lower.includes('tiffin') || lower.includes('meal')) benchmark = 120;
    ok(res, { suggestedPrice: benchmark });
  } catch (e) {
    next(e);
  }
};

exports.aiGenerateDescription = async (req, res, next) => {
  try {
    const { name, category, highlights } = req.body;
    const desc = `Freshly prepared ${name || 'item'} made with premium, authentic ingredients and traditional recipes. Handcrafted locally with supreme hygiene, care, and love. Best enjoyed fresh!`;
    ok(res, { generatedDescription: desc });
  } catch (e) {
    next(e);
  }
};
