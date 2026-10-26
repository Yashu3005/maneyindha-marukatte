const { v2: cloudinary } = require('cloudinary');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');
const User = require('../models/User');

const MAX_BYTES = 2 * 1024 * 1024;

const configured = () => !!(process.env.CLOUDINARY_CLOUD_NAME && process.env.CLOUDINARY_API_KEY && process.env.CLOUDINARY_API_SECRET);

// Decide the type from the file's own bytes — the client-declared mimetype/extension is not trusted.
function sniff(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length >= 12 && buf.subarray(0, 4).toString('latin1') === 'RIFF' && buf.subarray(8, 12).toString('latin1') === 'WEBP') return 'image/webp';
  return null;
}

// Test seam: replaced with a stand-in uploader in tests.
const provider = {
  upload(buffer, publicId) {
    cloudinary.config({
      cloud_name: process.env.CLOUDINARY_CLOUD_NAME, api_key: process.env.CLOUDINARY_API_KEY,
      api_secret: process.env.CLOUDINARY_API_SECRET, secure: true,
    });
    return new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        { folder: 'avatars', public_id: publicId, overwrite: true, invalidate: true, resource_type: 'image',
          transformation: [{ width: 512, height: 512, crop: 'limit' }] },
        (err, result) => (err ? reject(err) : resolve(result))
      );
      stream.end(buffer);
    });
  },
  destroy(publicId) {
    cloudinary.config({
      cloud_name: process.env.CLOUDINARY_CLOUD_NAME, api_key: process.env.CLOUDINARY_API_KEY,
      api_secret: process.env.CLOUDINARY_API_SECRET, secure: true,
    });
    return cloudinary.uploader.destroy(`avatars/${publicId}`, { invalidate: true });
  },
};

// One stable public id per user, so a re-upload replaces the previous picture instead of piling up.
const publicIdFor = (userId) => `user_${userId}`;

async function setAvatar(userId, file) {
  if (!file?.buffer?.length) throw new AppError('Choose an image to upload', 422);
  if (file.buffer.length > MAX_BYTES) throw new AppError('Image must be 2 MB or smaller', 413);
  if (!sniff(file.buffer)) throw new AppError('Only JPEG, PNG or WebP images are allowed', 415);
  if (!configured()) throw new AppError('Photo upload is not available right now', 503, 'UPLOAD_NOT_CONFIGURED');

  let result;
  try {
    result = await provider.upload(file.buffer, publicIdFor(userId));
  } catch (e) {
    logger.error(`Avatar upload failed: ${e?.http_code || ''} ${e?.message || 'unknown'}`);
    throw new AppError('Could not upload the photo. Please try again.', 502, 'UPLOAD_FAILED');
  }
  if (!result?.secure_url || !/^https:\/\//.test(result.secure_url)) {
    throw new AppError('Could not upload the photo. Please try again.', 502, 'UPLOAD_FAILED');
  }
  const user = await User.findById(userId);
  if (!user) throw new AppError('User not found', 404);
  user.avatarUrl = result.secure_url;
  await user.save();
  return user;
}

async function removeAvatar(userId) {
  const user = await User.findById(userId);
  if (!user) throw new AppError('User not found', 404);
  const had = !!user.avatarUrl;
  user.avatarUrl = undefined;
  await user.save();
  // Best effort: the profile is already cleared even if the remote delete fails.
  if (had && configured()) await provider.destroy(publicIdFor(userId)).catch((e) => logger.warn(`Avatar remote delete failed: ${e?.message}`));
  return user;
}

module.exports = { setAvatar, removeAvatar, sniff, MAX_BYTES, _provider: provider };
