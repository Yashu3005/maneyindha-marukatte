const Business = require('../models/Business');
require('../models/Category'); // must be registered before populate('category')
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');

exports.nearby = async (req, res, next) => {
  try {
    const { lat, lng, radiusKm = 10, page = 1, limit = 20 } = req.query;
    if (!lat || !lng) throw new AppError('lat and lng are required', 422);
    const businesses = await Business.find({
      'verification.status': 'approved',
      isActive: true,
      location: {
        $near: {
          $geometry: { type: 'Point', coordinates: [Number(lng), Number(lat)] },
          $maxDistance: Number(radiusKm) * 1000,
        },
      },
    })
      .skip((page - 1) * limit)
      .limit(Number(limit));
    ok(res, businesses, { page: Number(page), limit: Number(limit) });
  } catch (e) { next(e); }
};

exports.getById = async (req, res, next) => {
  try {
    const business = await Business.findById(req.params.id).populate('category');
    if (!business || !business.isActive) throw new AppError('Business not found', 404);
    ok(res, business);
  } catch (e) { next(e); }
};

exports.create = async (req, res, next) => {
  try {
    const body = { ...req.body, owner: req.user.id };
    // Onboarding sends a category NAME; resolve/create the Category doc.
    if (body.category && !/^[0-9a-fA-F]{24}$/.test(String(body.category))) {
      const Category = require('../models/Category');
      const name = String(body.category);
      const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
      const cat = await Category.findOneAndUpdate(
        { slug }, { name, slug, isActive: true }, { upsert: true, new: true });
      body.category = cat._id;
    }
    // Default location (refined in the Maps phase) so geo index stays valid.
    if (!body.location) body.location = { type: 'Point', coordinates: [77.5946, 12.9716] };
    body.slug = body.slug || `${String(body.name || 'shop').toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${Date.now().toString(36)}`;
    const business = await Business.create(body);
    ok(res, business, undefined, 201);
  } catch (e) { next(e); }
};

exports.uploadDocs = async (req, res, next) => {
  try {
    const adminService = require('../services/admin.service');
    ok(res, await adminService.uploadVerificationDocs(req.user.id, req.params.id, req.body.documents));
  } catch (e) { next(e); }
};

exports.list = async (req, res, next) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const filter = { 'verification.status': 'approved', isActive: true };
    const [items, total] = await Promise.all([
      require('../models/Business').find(filter).sort('-rating.avg')
        .skip((page - 1) * limit).limit(Number(limit)).populate('category', 'name'),
      require('../models/Business').countDocuments(filter),
    ]);
    ok(res, items, { page: Number(page), limit: Number(limit), total });
  } catch (e) { next(e); }
};

exports.mine = async (req, res, next) => {
  try {
    const items = await require('../models/Business')
      .find({ owner: req.user.id, isActive: true })
      .populate('category', 'name');
    ok(res, items);
  } catch (e) { next(e); }
};
