const Business = require('../models/Business');
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
    const business = await Business.create({ ...req.body, owner: req.user.id });
    ok(res, business, undefined, 201);
  } catch (e) { next(e); }
};

exports.uploadDocs = async (req, res, next) => {
  try {
    const adminService = require('../services/admin.service');
    ok(res, await adminService.uploadVerificationDocs(req.user.id, req.params.id, req.body.documents));
  } catch (e) { next(e); }
};
