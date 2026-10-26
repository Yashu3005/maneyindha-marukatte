const Business = require('../models/Business');
const Category = require('../models/Category');
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');
const { parsePage, isObjectId } = require('../utils/pagination');
const { slugify } = require('../utils/slug');
const { haversineKm } = require('../utils/geo');

// Public responses must never carry ID-proof/document URLs or reviewer internals.
const PUBLIC_EXCLUDE = '-verification.documents -verification.reviewedBy -verification.rejectionReason -location';

// Public shape: the exact point is replaced by the coarsened one (same field name, so clients are unaffected),
// and `locationSource` stays internal. Optionally adds the distance from a visitor-supplied point.
function toPublic(doc, from) {
  const out = typeof doc?.toObject === 'function' ? doc.toObject() : { ...doc };
  const pub = out.publicLocation;
  delete out.location;
  delete out.publicLocation;
  delete out.locationSource;
  if (pub?.coordinates?.length === 2) {
    out.location = pub;
    if (from) out.distanceKm = Math.round(haversineKm(from.lat, from.lng, pub.coordinates[1], pub.coordinates[0]) * 10) / 10;
  }
  return out;
}
const ADMIN_ROLES = ['admin', 'super_admin'];
const CREATE_FIELDS = ['name', 'description', 'category', 'logoUrl', 'bannerUrl', 'gallery', 'location',
  'address', 'workingHours', 'gstNumber', 'yearsOfExperience'];

const isOwnerOrAdmin = (user, business) =>
  !!user && (ADMIN_ROLES.includes(user.role) || String(business.owner) === String(user.id));

exports.nearby = async (req, res, next) => {
  try {
    const { lat, lng } = req.query;
    if (lat === undefined || lng === undefined) throw new AppError('lat and lng are required', 422);
    const latN = Number(lat);
    const lngN = Number(lng);
    if (!Number.isFinite(latN) || !Number.isFinite(lngN) || Math.abs(latN) > 90 || Math.abs(lngN) > 180) {
      throw new AppError('lat and lng must be valid coordinates', 422);
    }
    const radiusKm = Math.min(Math.max(Number(req.query.radiusKm) || 10, 0.1), 200);
    const { page, limit, skip } = parsePage(req.query);
    const businesses = await Business.find({
      'verification.status': 'approved',
      isActive: true,
      publicLocation: {
        $near: {
          $geometry: { type: 'Point', coordinates: [lngN, latN] },
          $maxDistance: radiusKm * 1000,
        },
      },
    })
      .select(PUBLIC_EXCLUDE)
      .skip(skip)
      .limit(limit);
    ok(res, businesses.map((b) => toPublic(b, { lat: latN, lng: lngN })), { page, limit });
  } catch (e) { next(e); }
};

exports.getById = async (req, res, next) => {
  try {
    const business = await Business.findById(req.params.id).populate('category');
    if (!business || !business.isActive) throw new AppError('Business not found', 404);
    const privileged = isOwnerOrAdmin(req.user, business);
    // Unapproved shops are only visible to their owner and admins.
    if (business.verification?.status !== 'approved' && !privileged) throw new AppError('Business not found', 404);
    if (privileged) return ok(res, business);
    const out = toPublic(business);
    if (out.verification) {
      delete out.verification.documents;
      delete out.verification.reviewedBy;
      delete out.verification.rejectionReason;
    }
    ok(res, out);
  } catch (e) { next(e); }
};

exports.create = async (req, res, next) => {
  try {
    // Whitelist: never spread req.body (it would allow self-approval via
    // verification.status, choosing owner/rating, etc.).
    const body = {};
    for (const key of CREATE_FIELDS) if (req.body[key] !== undefined) body[key] = req.body[key];
    body.owner = req.user.id;

    // Onboarding sends a category NAME; resolve/create the Category doc.
    if (body.category && !isObjectId(String(body.category))) {
      const name = String(body.category).trim();
      const slug = slugify(name);
      const cat = await Category.findOneAndUpdate(
        { slug }, { $setOnInsert: { name, slug, isActive: true } }, { upsert: true, new: true });
      body.category = cat._id;
    }
    // No made-up default location: a shop without one simply does not appear in "near me" until the owner sets it.
    body.locationSource = body.location ? (req.body.locationSource || 'manual') : 'unset';
    body.slug = `${slugify(body.name || 'shop')}-${Date.now().toString(36)}`;
    const business = await Business.create(body);
    ok(res, business, undefined, 201);
  } catch (e) { next(e); }
};

exports.setLocation = async (req, res, next) => {
  try {
    const business = await Business.findOne({ _id: req.params.id, owner: req.user.id, isActive: true });
    if (!business) throw new AppError('Business not found', 404); // other people's shops look the same as missing ones
    business.location = { type: 'Point', coordinates: [req.body.lng, req.body.lat] };
    business.locationSource = req.body.source;
    await business.save(); // pre-validate hook derives publicLocation
    ok(res, business);
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
    const { page, limit, skip } = parsePage(req.query);
    const filter = { 'verification.status': 'approved', isActive: true };
    const [items, total] = await Promise.all([
      Business.find(filter).select(PUBLIC_EXCLUDE).sort('-rating.avg')
        .skip(skip).limit(limit).populate('category', 'name'),
      Business.countDocuments(filter),
    ]);
    ok(res, items.map((b) => toPublic(b)), { page, limit, total });
  } catch (e) { next(e); }
};

exports.mine = async (req, res, next) => {
  try {
    const items = await Business
      .find({ owner: req.user.id, isActive: true })
      .populate('category', 'name');
    ok(res, items);
  } catch (e) { next(e); }
};
