const Business = require('../models/Business');
const Category = require('../models/Category');
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');
const { parsePage, isObjectId } = require('../utils/pagination');
const { slugify } = require('../utils/slug');
const { haversineKm } = require('../utils/geo');
const { coverOf } = require('../utils/shopPhoto');

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
  out.coverUrl = coverOf(out); // one consistent picture per shop for cards and lists
  if (out.promoVideo) {
    out.promoVideo = out.promoVideo.url && out.promoVideo.review?.status === 'approved'
      ? { url: out.promoVideo.url, posterUrl: out.promoVideo.posterUrl, duration: out.promoVideo.duration,
          title: out.promoVideo.title, caption: out.promoVideo.caption }
      : undefined;
  }
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

const escapeRegex = (str) => String(str).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const SORTS = { rating: '-rating.avg', newest: '-createdAt', name: 'name' };
// Own keys only: a query like ?sort=__proto__ must not resolve to Object.prototype.
const sortFor = (v) => (typeof v === 'string' && Object.prototype.hasOwnProperty.call(SORTS, v) ? SORTS[v] : undefined);

// Filters shared by "all shops" and "near me": category, text, minimum rating, open now, has a promo video.
async function discoveryFilter(query) {
  const filter = { 'verification.status': 'approved', isActive: true };
  if (query.category) {
    const c = String(query.category).trim();
    if (isObjectId(c)) filter.category = c;
    else {
      const cat = await Category.findOne({ name: new RegExp(`^${escapeRegex(c)}$`, 'i') }).select('_id');
      filter.category = cat ? cat._id : { $in: [] }; // unknown category -> no shops
    }
  }
  if (query.q && String(query.q).trim()) {
    filter.name = new RegExp(escapeRegex(String(query.q).trim().slice(0, 60)), 'i');
  }
  const minRating = Number(query.minRating);
  if (Number.isFinite(minRating) && minRating > 0) {
    filter['rating.avg'] = { $gte: Math.min(minRating, 5) };
    filter['rating.count'] = { $gte: 1 }; // "4★ and above" never includes unrated shops
  }
  if (query.openNow === 'true' || query.openNow === true) filter.isOpen = true;
  if (query.hasVideo === 'true' || query.hasVideo === true) filter['promoVideo.review.status'] = 'approved';
  return filter;
}

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
    const filter = await discoveryFilter(req.query);
    const sortKey = sortFor(req.query.sort);
    let query;
    if (sortKey) {
      // Re-ordered by rating/newest/name: bound by radius, the distance is still reported per shop.
      filter.publicLocation = { $geoWithin: { $centerSphere: [[lngN, latN], radiusKm / 6378.1] } };
      query = Business.find(filter).sort(sortKey);
    } else {
      // Default: nearest first.
      filter.publicLocation = { $near: { $geometry: { type: 'Point', coordinates: [lngN, latN] }, $maxDistance: radiusKm * 1000 } };
      query = Business.find(filter);
    }
    const businesses = await query.select(PUBLIC_EXCLUDE).skip(skip).limit(limit).populate('category', 'name');
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

// Submit the application for review. The documents themselves arrive through the upload endpoint;
// URLs in the body are ignored, so a client can never "attach" a link it does not own.
exports.uploadDocs = async (req, res, next) => {
  try {
    const docs = require('../services/verificationDoc.service');
    const business = await docs.submitForReview(req.user.id, req.params.id);
    ok(res, { id: business._id, status: business.verification.status });
  } catch (e) { next(e); }
};

exports.addDocument = async (req, res, next) => {
  try {
    const docs = require('../services/verificationDoc.service');
    ok(res, await docs.addDocument(req.user.id, req.params.id, req.file, req.body));
  } catch (e) { next(e); }
};

exports.listDocuments = async (req, res, next) => {
  try {
    const docs = require('../services/verificationDoc.service');
    ok(res, await docs.listDocuments(req.user.id, req.params.id));
  } catch (e) { next(e); }
};

exports.removeDocument = async (req, res, next) => {
  try {
    const docs = require('../services/verificationDoc.service');
    ok(res, await docs.removeDocument(req.user.id, req.params.id, req.params.docId));
  } catch (e) { next(e); }
};

exports.list = async (req, res, next) => {
  try {
    const { page, limit, skip } = parsePage(req.query);
    const filter = await discoveryFilter(req.query);
    const sort = sortFor(req.query.sort) || '-rating.avg';
    const [items, total] = await Promise.all([
      Business.find(filter).select(PUBLIC_EXCLUDE).sort(sort)
        .skip(skip).limit(limit).populate('category', 'name'),
      Business.countDocuments(filter),
    ]);
    ok(res, items.map((b) => toPublic(b)), { page, limit, total });
  } catch (e) { next(e); }
};

exports.photoSet = async (req, res, next) => {
  try { ok(res, await require('../services/shopPhoto.service').setCover(req.user.id, req.params.id, req.file)); } catch (e) { next(e); }
};
exports.photoRemove = async (req, res, next) => {
  try { ok(res, await require('../services/shopPhoto.service').removeCover(req.user.id, req.params.id)); } catch (e) { next(e); }
};

// Home-screen featured videos: the best-rated shops with an approved video (at most 3).
exports.promoAds = async (req, res, next) => {
  try {
    res.set('Cache-Control', 'public, max-age=60'); // the home screen asks once; ratings change slowly
    ok(res, await require('../services/promoVideo.service').featuredVideos(req.query.limit));
  } catch (e) { next(e); }
};

exports.mine = async (req, res, next) => {
  try {
    const items = await Business
      .find({ owner: req.user.id, $or: [{ isActive: true }, { 'suspension.at': { $ne: null } }] }) // a suspended shop stays visible to its owner
      .populate('category', 'name');
    ok(res, items);
  } catch (e) { next(e); }
};

// ---- Promo ("story") video ----
exports.promoSignature = async (req, res, next) => {
  try {
    res.set('Cache-Control', 'no-store');
    ok(res, await require('../services/promoVideo.service').createUploadSignature(req.user.id, req.params.id));
  } catch (e) { next(e); }
};
exports.promoAttach = async (req, res, next) => {
  try { ok(res, await require('../services/promoVideo.service').attachVideo(req.user.id, req.params.id, req.body)); } catch (e) { next(e); }
};
exports.promoRemove = async (req, res, next) => {
  try { ok(res, await require('../services/promoVideo.service').removeVideo(req.user.id, req.params.id)); } catch (e) { next(e); }
};

// ---- Ratings ----
// Average, count and the 1-5 star spread for a shop — computed from its real reviews.
exports.ratingSummary = async (req, res, next) => {
  try {
    if (!isObjectId(req.params.id)) throw new AppError('Business not found', 404);
    const business = await Business.findOne({ _id: req.params.id, isActive: true, 'verification.status': 'approved' }).select('rating');
    if (!business) throw new AppError('Business not found', 404);
    ok(res, await require('../services/review.service').businessSummary(business._id));
  } catch (e) { next(e); }
};
