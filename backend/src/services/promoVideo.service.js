const crypto = require('crypto');
const { v2: cloudinary } = require('cloudinary');
const Business = require('../models/Business');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');

// Promo ("story") videos. Videos are too large for a serverless request body, so the browser uploads them
// straight to Cloudinary using a short-lived signature from us. The server then CHECKS what was uploaded
// (size, length, format, and that it sits under this shop's own folder) before it is ever shown to customers.
const MAX_BYTES = 40 * 1024 * 1024;
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
        transformation: [{ width: 720, crop: 'limit', quality: 'auto' }] }),
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
  if (!(info.bytes > 0) || info.bytes > MAX_BYTES) return reject('The video must be 40 MB or smaller');
  if (!(info.duration > 0) || info.duration > MAX_SECONDS + 0.5) return reject(`The video must be ${MAX_SECONDS} seconds or shorter`);

  const previous = business.promoVideo?.publicId;
  const urls = provider.urls(publicId);
  business.promoVideo = {
    publicId, url: urls.url, posterUrl: urls.posterUrl,
    duration: Math.round(info.duration * 10) / 10, bytes: info.bytes, format: String(info.format).toLowerCase(),
    title: String(title || '').trim().slice(0, 80) || undefined,
    caption: String(caption || '').trim().slice(0, 240) || undefined,
    uploadedAt: new Date(),
  };
  await business.save();
  if (previous && previous !== publicId) {
    await Promise.resolve(provider.destroy(previous)).catch((e) => logger.warn(`Old promo video cleanup failed: ${e?.message}`));
  }
  return publicShape(business.promoVideo);
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

module.exports = {
  createUploadSignature, attachVideo, removeVideo, adminRemoveVideo, publicShape,
  MAX_BYTES, MAX_SECONDS, FORMATS, _provider: provider,
};
