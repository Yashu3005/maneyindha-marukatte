const { v2: cloudinary } = require('cloudinary');
const crypto = require('crypto');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');
const { sniff } = require('./avatar.service');

const MAX_BYTES = 3 * 1024 * 1024;
const configured = () => !!(process.env.CLOUDINARY_CLOUD_NAME && process.env.CLOUDINARY_API_KEY && process.env.CLOUDINARY_API_SECRET);

// Test seam: replaced with a stand-in uploader in tests.
const provider = {
  upload(buffer, publicId) {
    cloudinary.config({
      cloud_name: process.env.CLOUDINARY_CLOUD_NAME, api_key: process.env.CLOUDINARY_API_KEY,
      api_secret: process.env.CLOUDINARY_API_SECRET, secure: true,
    });
    return new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        { folder: 'products', public_id: publicId, resource_type: 'image',
          transformation: [{ width: 1280, height: 1280, crop: 'limit' }] },
        (err, result) => (err ? reject(err) : resolve(result))
      );
      stream.end(buffer);
    });
  },
};

/** Validates (by the file's own bytes) and stores one product photo; returns its https URL. */
async function uploadProductPhoto(userId, file) {
  if (!file?.buffer?.length) throw new AppError('Choose an image to upload', 422);
  if (file.buffer.length > MAX_BYTES) throw new AppError('Image must be 3 MB or smaller', 413);
  if (!sniff(file.buffer)) throw new AppError('Only JPEG, PNG or WebP images are allowed', 415);
  if (!configured()) throw new AppError('Photo upload is not available right now', 503, 'UPLOAD_NOT_CONFIGURED');
  let result;
  try {
    result = await provider.upload(file.buffer, `p_${userId}_${crypto.randomBytes(6).toString('hex')}`);
  } catch (e) {
    logger.error(`Product photo upload failed: ${e?.http_code || ''} ${e?.message || 'unknown'}`);
    throw new AppError('Could not upload the photo. Please try again.', 502, 'UPLOAD_FAILED');
  }
  if (!result?.secure_url || !/^https:\/\//.test(result.secure_url)) {
    throw new AppError('Could not upload the photo. Please try again.', 502, 'UPLOAD_FAILED');
  }
  return result.secure_url;
}

module.exports = { uploadProductPhoto, MAX_BYTES, _provider: provider };
