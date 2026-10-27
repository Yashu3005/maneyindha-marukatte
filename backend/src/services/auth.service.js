const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const RefreshSession = require('../models/RefreshSession');
const AppError = require('../utils/AppError');
const otpService = require('./otp.service');

const PRIVILEGED_ROLES = ['admin', 'super_admin'];
const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

function signTokens(user, sid) {
  const payload = { id: user._id, role: user.role, sid };
  return {
    accessToken: jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '15m' }),
    refreshToken: jwt.sign(payload, process.env.JWT_REFRESH_SECRET, { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d' }),
  };
}

/**
 * Creates (or, when `sid` is given, refreshes) the server-side session behind a token pair.
 * Deleting that session — logout — makes the refresh token unusable immediately.
 */
async function issueSession(user, sid) {
  const id = sid || crypto.randomUUID();
  await RefreshSession.findOneAndUpdate(
    { sid: id },
    { $set: { user: user._id, expiresAt: new Date(Date.now() + REFRESH_TTL_MS) } },
    { upsert: true }
  );
  return signTokens(user, id);
}

function sanitize(user) {
  const { _id, name, email, phone, role, avatarUrl, language, username, profileComplete, emailVerified, addresses, bankAccount } = user;
  return { id: _id, _id, name, email, phone, role, avatarUrl, language, username, profileComplete, emailVerified, addresses, bankAccount };
}

exports.issueSession = issueSession;
exports.sanitize = sanitize;

exports.register = async ({ name, email, phone, password, role }) => {
  const or = [];
  if (email) or.push({ email });
  if (phone) or.push({ phone });
  const existing = or.length ? await User.findOne({ $or: or }) : null;
  if (existing) throw new AppError('Account already exists', 409);
  const passwordHash = await bcrypt.hash(password, 12);
  const user = await User.create({ name, email, phone, passwordHash, role, profileComplete: true });
  return { user: sanitize(user), ...(await issueSession(user)) };
};

exports.login = async ({ email, phone, username, password }) => {
  const query = email ? { email } : phone ? { phone } : { username };
  const user = await User.findOne(query).select('+passwordHash');
  if (!user || !(await bcrypt.compare(password, user.passwordHash || ''))) {
    throw new AppError('Invalid credentials', 401);
  }
  if (user.isActive === false) throw new AppError('Account disabled', 403);
  // The administrator signs in only through /auth/admin/login (credentials held in server configuration).
  if (PRIVILEGED_ROLES.includes(user.role)) throw new AppError('Invalid credentials', 401);
  return { user: sanitize(user), ...(await issueSession(user)) };
};

exports.refresh = async (refreshToken) => {
  if (!refreshToken || typeof refreshToken !== 'string') throw new AppError('Refresh token required', 400);
  try {
    const payload = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    if (!payload.sid) throw new Error('legacy token');
    const session = await RefreshSession.findOne({ sid: payload.sid, user: payload.id });
    if (!session) throw new Error('revoked');
    const user = await User.findById(payload.id);
    if (!user || !user.isActive) throw new Error('inactive');
    return await issueSession(user, payload.sid);
  } catch {
    throw new AppError('Invalid refresh token', 401);
  }
};

/** Logout: revoke the session behind a refresh token. Always succeeds (idempotent). */
exports.logout = async (refreshToken) => {
  try {
    const payload = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    if (payload.sid) await RefreshSession.deleteOne({ sid: payload.sid, user: payload.id });
  } catch { /* unknown/expired token: nothing to revoke */ }
  return { loggedOut: true };
};

exports.logoutAll = async (userId) => {
  await RefreshSession.deleteMany({ user: userId });
  return { loggedOut: true };
};

// --- Email OTP (delivered through Resend; see otp.service / email.service) ---
exports.sendOtp = (email) => otpService.requestOtp(email);

exports.verifyOtp = async ({ email, otp }) => {
  const verifiedEmail = await otpService.verifyOtp(email, otp);

  let user = await User.findOne({ email: verifiedEmail });
  let isNewUser = false;
  if (!user) {
    isNewUser = true;
    user = await User.create({
      name: 'New Member', email: verifiedEmail, emailVerified: true,
      role: 'customer', profileComplete: false,
    });
  } else if (!user.emailVerified) {
    user.emailVerified = true;
    await user.save();
  }
  if (!user.isActive) throw new AppError('Account disabled', 403);
  // Email-OTP must never be a way into privileged accounts.
  if (PRIVILEGED_ROLES.includes(user.role)) throw new AppError('Use password login for this account', 403);
  return { user: sanitize(user), ...(await issueSession(user)), isNewUser };
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
  return { user: sanitize(user), ...(await issueSession(user)) };
};
