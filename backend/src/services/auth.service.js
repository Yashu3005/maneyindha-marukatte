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

// --- OTP (demo-friendly; wire an email provider before production) ---
const otpStore = new Map(); // email -> { otp, expires }
const DEMO_OTP = '029403';

exports.sendOtp = async (email) => {
  if (!email) throw new AppError('Email required', 422);
  const otp = String(crypto.randomInt(100000, 999999));
  otpStore.set(email.toLowerCase(), { otp, expires: Date.now() + 10 * 60 * 1000 });
  const out = { sent: true };
  if (process.env.NODE_ENV !== 'production') out.demoOtp = DEMO_OTP;
  return out;
};

exports.verifyOtp = async ({ email, otp }) => {
  if (!email || !otp) throw new AppError('Email and OTP required', 422);
  const rec = otpStore.get(email.toLowerCase());
  const demoOk = process.env.NODE_ENV !== 'production' && otp === DEMO_OTP;
  const realOk = rec && rec.expires > Date.now() && rec.otp === otp;
  if (!demoOk && !realOk) throw new AppError('Invalid or expired OTP', 401);
  otpStore.delete(email.toLowerCase());

  let user = await User.findOne({ email: email.toLowerCase() });
  let isNewUser = false;
  if (!user) {
    isNewUser = true;
    user = await User.create({
      name: 'New Member', email: email.toLowerCase(),
      role: 'customer', profileComplete: false,
    });
  }
  if (!user.isActive) throw new AppError('Account disabled', 403);
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
