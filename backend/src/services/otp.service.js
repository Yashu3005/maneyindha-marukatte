const crypto = require('crypto');
const OtpToken = require('../models/OtpToken');
const AppError = require('../utils/AppError');
const emailService = require('./email.service');

const OTP_TTL_MS = 5 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;
const PURPOSE_LOGIN = 'login';

// Keyed hash (HMAC-SHA256). Binding email + purpose into the message means a code
// issued for one account/purpose can never verify for another.
function hashCode(email, purpose, code) {
  const key = process.env.OTP_HMAC_SECRET || process.env.JWT_SECRET;
  if (!key) throw new AppError('Server is not configured', 500);
  return crypto.createHmac('sha256', `otp:${key}`).update(`${purpose}:${email}:${code}`).digest('hex');
}

const safeEqualHex = (a, b) => {
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

const normalizeEmail = (email) => String(email).trim().toLowerCase();

/**
 * Issue a new code (superseding any previous one) and email it via Resend.
 * The response never contains the code and is identical for known/unknown emails.
 */
exports.requestOtp = async (rawEmail, purpose = PURPOSE_LOGIN) => {
  const email = normalizeEmail(rawEmail);
  const now = Date.now();

  const existing = await OtpToken.findOne({ email, purpose });
  if (existing && now - existing.lastSentAt.getTime() < RESEND_COOLDOWN_MS) {
    const retryAfter = Math.ceil((RESEND_COOLDOWN_MS - (now - existing.lastSentAt.getTime())) / 1000);
    const err = new AppError(`Please wait ${retryAfter}s before requesting another code`, 429, 'OTP_COOLDOWN');
    err.retryAfterSeconds = retryAfter;
    throw err;
  }

  const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
  const doc = await OtpToken.findOneAndUpdate(
    { email, purpose },
    { $set: { codeHash: hashCode(email, purpose, code), expiresAt: new Date(now + OTP_TTL_MS), attempts: 0, lastSentAt: new Date(now), consumedAt: null } },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );

  try {
    await emailService.sendOtpEmail({ to: email, code, expiresMinutes: OTP_TTL_MS / 60000 });
  } catch (err) {
    // Nothing was delivered: drop the unusable code (and its cooldown) so the user can retry at once.
    await OtpToken.deleteOne({ _id: doc._id }).catch(() => {});
    throw err;
  }
  return { sent: true, expiresInSeconds: OTP_TTL_MS / 1000, resendAfterSeconds: RESEND_COOLDOWN_MS / 1000 };
};

/** Verifies and consumes a code. Resolves with the normalized email on success. */
exports.verifyOtp = async (rawEmail, code, purpose = PURPOSE_LOGIN) => {
  const email = normalizeEmail(rawEmail);
  const invalid = () => new AppError('Invalid or expired code', 401, 'OTP_INVALID');

  // Atomically spend one attempt on a live, unused code. Concurrent guesses cannot exceed MAX_ATTEMPTS.
  const doc = await OtpToken.findOneAndUpdate(
    { email, purpose, consumedAt: null, expiresAt: { $gt: new Date() }, attempts: { $lt: MAX_ATTEMPTS } },
    { $inc: { attempts: 1 } },
    { new: true }
  );
  if (!doc) {
    const stale = await OtpToken.findOne({ email, purpose, consumedAt: null, expiresAt: { $gt: new Date() } });
    if (stale && stale.attempts >= MAX_ATTEMPTS) {
      throw new AppError('Too many incorrect attempts. Request a new code.', 429, 'OTP_LOCKED');
    }
    throw invalid();
  }

  if (!safeEqualHex(hashCode(email, purpose, code), doc.codeHash)) throw invalid();

  // Single use: only one concurrent request can flip consumedAt.
  const consumed = await OtpToken.updateOne({ _id: doc._id, consumedAt: null }, { $set: { consumedAt: new Date() } });
  if (consumed.modifiedCount !== 1) throw invalid();
  return email;
};

exports.constants = { OTP_TTL_MS, RESEND_COOLDOWN_MS, MAX_ATTEMPTS };
