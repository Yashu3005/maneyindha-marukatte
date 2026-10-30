const { v2: cloudinary } = require('cloudinary');
const Business = require('../models/Business');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');
const { sniff } = require('./avatar.service');

// The shop's cover photo (shown on the customer home, in lists and on the shop page). It uses the same image
// provider and the same field (bannerUrl) as the rest of the app; no second image system.
const MAX_BYTES = 3 * 1024 * 1024;
const configured = () => !!(process.env.CLOUDINARY_CLOUD_NAME && process.env.CLOUDINARY_API_KEY && process.env.CLOUDINARY_API_SECRET);
const config = () => cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME, api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET, secure: true,
});

// Test seam: replaced in tests so nothing touches the network.
const provider = {
  upload(buffer, publicId) {
    config();
    return new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        { folder: 'shops', public_id: publicId, overwrite: true, invalidate: true, resource_type: 'image',
          transformation: [{ width: 1280, height: 1280, crop: 'limit' }] },
        (err, result) => (err ? reject(err) : resolve(result)));
      stream.end(buffer);
    });
  },
  destroy(publicId) {
    config();
    return cloudinary.uploader.destroy(`shops/${publicId}`, { invalidate: true });
  },
};

// One stable id per shop, so a new photo replaces the old one instead of piling up.
const publicIdFor = (businessId) => `shop_${businessId}`;

async function ownedShop(ownerId, businessId) {
  const business = await Business.findOne({ _id: businessId, owner: ownerId, isActive: true });
  if (!business) throw new AppError('Business not found', 404);
  return business;
}

async function setCover(ownerId, businessId, file) {
  const business = await ownedShop(ownerId, businessId);
  if (!file?.buffer?.length) throw new AppError('Choose an image to upload', 422);
  if (file.buffer.length > MAX_BYTES) throw new AppError('Image must be 3 MB or smaller', 413);
  if (!sniff(file.buffer)) throw new AppError('Only JPEG, PNG or WebP images are allowed', 415);
  if (!configured()) throw new AppError('Photo upload is not available right now', 503, 'UPLOAD_NOT_CONFIGURED');
  let result;
  try {
    result = await provider.upload(file.buffer, publicIdFor(business._id));
  } catch (e) {
    logger.error(`Shop photo upload failed: ${e?.http_code || ''} ${e?.message || 'unknown'}`);
    throw new AppError('Could not upload the photo. Please try again.', 502, 'UPLOAD_FAILED');
  }
  if (!result?.secure_url || !/^https:\/\//.test(result.secure_url)) {
    throw new AppError('Could not upload the photo. Please try again.', 502, 'UPLOAD_FAILED');
  }
  business.bannerUrl = result.secure_url;
  await business.save();
  return { bannerUrl: business.bannerUrl };
}

async function removeCover(ownerId, businessId) {
  const business = await ownedShop(ownerId, businessId);
  const had = !!business.bannerUrl;
  business.bannerUrl = undefined;
  await business.save();
  if (had && configured()) await Promise.resolve(provider.destroy(publicIdFor(business._id))).catch((e) => logger.warn(`Shop photo remote delete failed: ${e?.message}`));
  return { removed: had };
}

module.exports = { setCover, removeCover, MAX_BYTES, _provider: provider };
