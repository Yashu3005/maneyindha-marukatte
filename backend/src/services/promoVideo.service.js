const crypto = require('crypto');
const { v2: cloudinary } = require('cloudinary');
const Business = require('../models/Business');
const AppError = require('../utils/AppError');
const { coverOf } = require('../utils/shopPhoto');
const logger = require('../utils/logger');

// Promo ("story") videos. Videos are too large for a serverless request body, so the browser uploads them
// straight to Cloudinary using a short-lived signature from us. The server then CHECKS what was uploaded
// (size, length, format, and that it sits under this shop's own folder) before it is ever shown to customers.
const MAX_BYTES = 100 * 1024 * 1024; // Cloudinary's free plan accepts videos up to 100 MB
const MAX_SECONDS = 60;
const FORMATS = ['mp4', 'mov', 'webm'];

const configured = () => !!(process.env.CLOUDINARY_CLOUD_NAME && process.env.CLOUDINARY_API_KEY && process.env.CLOUDINARY_API_SECRET);
const config = () => cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME, api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET, secure: true,
});

// Test seam: stand-ins replace these in tests so nothing touches the network.
const provider = {
  sign(params) {
    config();
    return cloudinary.utils.api_sign_request(params, process.env.CLOUDINARY_API_SECRET);
  },
  resource(publicId) {
    config();
    return cloudinary.api.resource(publicId, { resource_type: 'video' });
  },
  destroy(publicId) {
    config();
    return cloudinary.uploader.destroy(publicId, { resource_type: 'video', invalidate: true });
  },
  urls(publicId) {
    config();
    return {
      url: cloudinary.url(publicId, { resource_type: 'video', secure: true, format: 'mp4',
        transformation: [{ width: 720, crop: 'limit', quality: 'auto', end_offset: MAX_SECONDS }] }), // playback is capped at the limit
      posterUrl: cloudinary.url(publicId, { resource_type: 'video', secure: true, format: 'jpg',
        transformation: [{ width: 720, crop: 'limit', start_offset: '0' }] }),
    };
  },
};

const idPattern = (businessId) => new RegExp(`^promo/${businessId}/[a-f0-9]{24}$`);

async function ownedApprovedShop(ownerId, businessId) {
  const business = await Business.findOne({ _id: businessId, owner: ownerId, isActive: true });
  if (!business) throw new AppError('Business not found', 404);
  if (business.verification?.status !== 'approved') {
    throw new AppError('Your shop can add a video once it has been approved', 403, 'BUSINESS_NOT_APPROVED');
  }
  return business;
}

/** Step 1: a signature the browser uses to upload one video to this shop's folder. */
async function createUploadSignature(ownerId, businessId) {
  const business = await ownedApprovedShop(ownerId, businessId);
  if (!configured()) throw new AppError('Video upload is not available right now', 503, 'UPLOAD_NOT_CONFIGURED');
  const publicId = `promo/${business._id}/${crypto.randomBytes(12).toString('hex')}`;
  const params = { allowed_formats: FORMATS.join(','), public_id: publicId, timestamp: Math.floor(Date.now() / 1000) };
  const signature = provider.sign(params);
  return {
    uploadUrl: `https://api.cloudinary.com/v1_1/${process.env.CLOUDINARY_CLOUD_NAME}/video/upload`,
    // Only these fields (plus the file) may be sent; the API secret never leaves the server.
    fields: { ...params, api_key: process.env.CLOUDINARY_API_KEY, signature },
    publicId,
    limits: { maxBytes: MAX_BYTES, maxSeconds: MAX_SECONDS, formats: FORMATS },
  };
}

const publicShape = (v) => (v?.url ? { url: v.url, posterUrl: v.posterUrl, duration: v.duration, title: v.title, caption: v.caption } : null);
// What the owner gets back: the same plus where the video is in review.
const ownerShape = (v) => (v?.url ? { ...publicShape(v), status: v.review?.status || 'pending', reason: v.review?.reason } : null);

/** Step 2: the browser reports the finished upload; we verify it with Cloudinary before accepting it. */
async function attachVideo(ownerId, businessId, { publicId, title, caption }) {
  const business = await ownedApprovedShop(ownerId, businessId);
  if (!configured()) throw new AppError('Video upload is not available right now', 503, 'UPLOAD_NOT_CONFIGURED');
  if (!idPattern(business._id).test(String(publicId || ''))) throw new AppError('Invalid upload reference', 422);

  let info;
  try {
    info = await provider.resource(publicId);
  } catch (e) {
    if (e?.http_code === 404) throw new AppError('We could not find that upload. Please try again.', 422, 'UPLOAD_NOT_FOUND');
    logger.error(`Promo video lookup failed: ${e?.http_code || ''} ${e?.message || 'unknown'}`);
    throw new AppError('Could not check the video. Please try again.', 502, 'UPLOAD_FAILED');
  }

  const reject = async (message) => {
    await Promise.resolve(provider.destroy(publicId)).catch((e) => logger.warn(`Promo video cleanup failed: ${e?.message}`));
    throw new AppError(message, 422, 'VIDEO_INVALID');
  };
  if (!info || !FORMATS.includes(String(info.format || '').toLowerCase())) return reject('Please upload an MP4, MOV or WebM video');
  if (!(info.bytes > 0) || info.bytes > MAX_BYTES) return reject('The video must be 100 MB or smaller');
  // Cloudinary does not always report the length straight after an upload. When it does not, the video is
  // accepted (size is still checked) and playback is cut at the limit by the delivery URL.
  const reported = [info.duration, info.video?.duration, info.video_metadata?.duration].find((v) => v !== undefined && v !== null);
  let duration;
  if (reported === undefined) {
    logger.warn(`Promo video length not reported by Cloudinary (fields: ${Object.keys(info).slice(0, 30).join(',')})`);
  } else {
    duration = Number(reported);
    if (!(duration > 0) || duration > MAX_SECONDS + 0.5) return reject(`The video must be ${MAX_SECONDS} seconds or shorter`);
  }

  const previous = business.promoVideo?.publicId;
  const urls = provider.urls(publicId);
  business.promoVideo = {
    publicId, url: urls.url, posterUrl: urls.posterUrl,
    duration: duration === undefined ? undefined : Math.round(duration * 10) / 10, bytes: info.bytes, format: String(info.format).toLowerCase(),
    title: String(title || '').trim().slice(0, 80) || undefined,
    caption: String(caption || '').trim().slice(0, 240) || undefined,
    uploadedAt: new Date(),
    review: { status: 'pending' }, // not shown to customers until the admin approves it
  };
  await business.save();
  if (previous && previous !== publicId) {
    await Promise.resolve(provider.destroy(previous)).catch((e) => logger.warn(`Old promo video cleanup failed: ${e?.message}`));
  }
  return ownerShape(business.promoVideo);
}

async function removeVideo(ownerId, businessId) {
  const business = await Business.findOne({ _id: businessId, owner: ownerId, isActive: true });
  if (!business) throw new AppError('Business not found', 404);
  return clear(business);
}

// Admin takedown: works on any shop.
async function adminRemoveVideo(businessId) {
  const business = await Business.findById(businessId);
  if (!business) throw new AppError('Business not found', 404);
  return clear(business);
}

async function clear(business) {
  const previous = business.promoVideo?.publicId;
  business.promoVideo = undefined;
  await business.save();
  if (previous && configured()) {
    await Promise.resolve(provider.destroy(previous)).catch((e) => logger.warn(`Promo video remote delete failed: ${e?.message}`));
  }
  return { removed: !!previous };
}

const AD_STATUSES = ['pending', 'approved', 'rejected'];

/** Admin queue: shops whose video is in the given review state (oldest first). */
async function listForReview(status = 'pending') {
  if (!AD_STATUSES.includes(status)) throw new AppError('Invalid status', 422);
  // A video saved before reviews existed has no status, so it counts as pending.
  const match = status === 'pending'
    ? { $or: [{ 'promoVideo.review.status': 'pending' }, { 'promoVideo.review.status': { $exists: false } }] }
    : { 'promoVideo.review.status': status };
  const shops = await Business.find({ isActive: true, 'promoVideo.url': { $exists: true }, ...match })
    .select('name promoVideo').sort('promoVideo.uploadedAt').limit(100).lean();
  return shops.map((b) => ({
    businessId: b._id, name: b.name,
    promoVideo: { ...publicShape(b.promoVideo), uploadedAt: b.promoVideo.uploadedAt,
      status: b.promoVideo.review?.status || 'pending', reason: b.promoVideo.review?.reason },
  }));
}

/** Admin decision. Rejecting needs a short reason the owner will see. */
async function reviewVideo(businessId, action, reason) {
  const business = await Business.findById(businessId);
  if (!business?.promoVideo?.url) throw new AppError('This shop has no video to review', 404);
  if (action === 'approve') {
    business.promoVideo.review = { status: 'approved', reviewedAt: new Date() };
  } else if (action === 'reject') {
    const why = String(reason || '').trim().slice(0, 300);
    if (!why) throw new AppError('Please give a short reason for rejecting', 422);
    business.promoVideo.review = { status: 'rejected', reason: why, reviewedAt: new Date() };
  } else {
    throw new AppError('Invalid action', 422);
  }
  await business.save();
  return { businessId: business._id, status: business.promoVideo.review.status };
}

/**
 * The featured videos for the home banner: the best-rated shops (at most `limit`, never more than 3) that have an
 * approved, playable video. Deterministic, from real ratings only.
 *  - A shop's score is a weighted average (Bayesian): ratings pull towards the average of all rated shops until a shop
 *    has about PRIOR_VOTES reviews, so one 5-star review does not beat an established 4.8.
 *  - Ties go to the shop with more reviews, then the older shop (stable order).
 *  - Shops with no ratings come after every rated shop; no rating is ever invented.
 */
const PRIOR_VOTES = 5;
async function featuredVideos(limit = 3) {
  const n = Math.min(Math.max(parseInt(limit, 10) || 3, 1), 3);
  const shops = await Business.find({
    isActive: true, deletedAt: null, 'verification.status': 'approved',
    'promoVideo.review.status': 'approved', 'promoVideo.url': { $regex: '^https://' },
  }).select('name logoUrl bannerUrl gallery rating promoVideo').limit(200).lean();

  const rated = shops.filter((b) => (b.rating?.count || 0) > 0);
  const mean = rated.length ? rated.reduce((t, b) => t + b.rating.avg, 0) / rated.length : 0;
  const scoreOf = (b) => (b.rating.count / (b.rating.count + PRIOR_VOTES)) * b.rating.avg
    + (PRIOR_VOTES / (b.rating.count + PRIOR_VOTES)) * mean;
  const byId = (x, y) => String(x._id).localeCompare(String(y._id));
  rated.sort((x, y) => (scoreOf(y) - scoreOf(x)) || (y.rating.count - x.rating.count) || byId(x, y));
  const unrated = shops.filter((b) => !((b.rating?.count || 0) > 0)).sort(byId);

  return [...rated, ...unrated].slice(0, n).map((b) => ({
    businessId: b._id, name: b.name, coverUrl: coverOf(b),
    rating: (b.rating?.count || 0) > 0 ? { avg: b.rating.avg, count: b.rating.count } : null,
    video: publicShape(b.promoVideo),
  }));
}

module.exports = {
  createUploadSignature, attachVideo, removeVideo, adminRemoveVideo, publicShape,
  listForReview, reviewVideo, featuredVideos,
  MAX_BYTES, MAX_SECONDS, FORMATS, _provider: provider,
};
