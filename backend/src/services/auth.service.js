const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const AppError = require('../utils/AppError');

function issueTokens(user) {
  const payload = { id: user._id, role: user.role };
  return {
    accessToken: jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '15m' }),
    refreshToken: jwt.sign(payload, process.env.JWT_REFRESH_SECRET, { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d' }),
  };
}

function sanitize(user) {
  const { _id, name, email, phone, role, avatarUrl, language, username, profileComplete, addresses, bankAccount } = user;
  return { id: _id, _id, name, email, phone, role, avatarUrl, language, username, profileComplete, addresses, bankAccount };
}

exports.issueTokens = issueTokens;
exports.sanitize = sanitize;

exports.register = async ({ name, email, phone, password, role }) => {
  const or = [];
  if (email) or.push({ email });
  if (phone) or.push({ phone });
  const existing = or.length ? await User.findOne({ $or: or }) : null;
  if (existing) throw new AppError('Account already exists', 409);
  const passwordHash = await bcrypt.hash(password, 12);
  const user = await User.create({ name, email, phone, passwordHash, role, profileComplete: true });
  return { user: sanitize(user), ...issueTokens(user) };
};

exports.login = async ({ email, phone, username, password }) => {
  const query = email ? { email } : phone ? { phone } : { username };
  const user = await User.findOne(query).select('+passwordHash');
  if (!user || !(await bcrypt.compare(password, user.passwordHash || ''))) {
    throw new AppError('Invalid credentials', 401);
  }
  if (user.isActive === false) throw new AppError('Account disabled', 403);
  return { user: sanitize(user), ...issueTokens(user) };
};

exports.refresh = async (refreshToken) => {
  if (!refreshToken) throw new AppError('Refresh token required', 400);
  try {
    const payload = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    const user = await User.findById(payload.id);
    if (!user || !user.isActive) throw new Error();
    return issueTokens(user);
  } catch {
    throw new AppError('Invalid refresh token', 401);
  }
};

// --- OTP ---
// NOTE: no email/SMS provider is wired up yet, so real OTPs are generated but not
// delivered. The fixed demo OTP is a development convenience ONLY: it must be opted
// into with ALLOW_DEMO_OTP=true and is never honoured when NODE_ENV=production.
const otpStore = new Map(); // email -> { otp, expires, attempts }
const DEMO_OTP = '029403';
const MAX_OTP_ATTEMPTS = 5;
const demoOtpEnabled = () => process.env.ALLOW_DEMO_OTP === 'true' && process.env.NODE_ENV !== 'production';
const PRIVILEGED_ROLES = ['admin', 'super_admin'];

exports.sendOtp = async (email) => {
  if (!email || typeof email !== 'string') throw new AppError('Email required', 422);
  const otp = String(crypto.randomInt(100000, 1000000));
  otpStore.set(email.toLowerCase(), { otp, expires: Date.now() + 10 * 60 * 1000, attempts: 0 });
  const out = { sent: true };
  if (demoOtpEnabled()) out.demoOtp = DEMO_OTP;
  return out;
};

exports.verifyOtp = async ({ email, otp }) => {
  if (!email || !otp || typeof email !== 'string' || typeof otp !== 'string') {
    throw new AppError('Email and OTP required', 422);
  }
  const key = email.toLowerCase();
  const rec = otpStore.get(key);
  if (rec && rec.attempts >= MAX_OTP_ATTEMPTS) {
    otpStore.delete(key);
    throw new AppError('Too many attempts, request a new OTP', 429);
  }
  const demoOk = demoOtpEnabled() && otp === DEMO_OTP;
  const realOk = rec && rec.expires > Date.now() && rec.otp === otp;
  if (!demoOk && !realOk) {
    if (rec) rec.attempts += 1;
    throw new AppError('Invalid or expired OTP', 401);
  }
  otpStore.delete(key);

  let user = await User.findOne({ email: key });
  let isNewUser = false;
  if (!user) {
    isNewUser = true;
    user = await User.create({
      name: 'New Member', email: key,
      role: 'customer', profileComplete: false,
    });
  }
  if (!user.isActive) throw new AppError('Account disabled', 403);
  // Email-OTP must never be a way into privileged accounts.
  if (PRIVILEGED_ROLES.includes(user.role)) throw new AppError('Use password login for this account', 403);
  return { user: sanitize(user), ...issueTokens(user), isNewUser };
};

// --- Firebase exchange (Phase 2) ---
const { getFirebase } = require('../config/firebase');

exports.exchangeFirebaseToken = async ({ idToken, role, name }) => {
  if (!idToken) throw new AppError('idToken required', 422);
  let decoded;
  try {
    decoded = await getFirebase().auth().verifyIdToken(idToken);
  } catch {
    throw new AppError('Invalid Firebase token', 401);
  }
  let user = await User.findOne({ firebaseUid: decoded.uid });
  if (!user) {
    const safeRole = ['customer', 'entrepreneur', 'delivery_partner'].includes(role) ? role : 'customer';
    user = await User.create({
      firebaseUid: decoded.uid,
      name: name || decoded.name || 'User',
      email: decoded.email,
      phone: decoded.phone_number?.replace('+91', ''),
      role: safeRole,
    });
  }
  if (!user.isActive) throw new AppError('Account disabled', 403);
  return { user: sanitize(user), ...issueTokens(user) };
};
