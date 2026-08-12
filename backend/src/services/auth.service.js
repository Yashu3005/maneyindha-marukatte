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

exports.register = async ({ name, email, phone, password, role }) => {
  const existing = await User.findOne({ $or: [{ email }, { phone }].filter((c) => Object.values(c)[0]) });
  if (existing) throw new AppError('Account already exists', 409);
  const passwordHash = await bcrypt.hash(password, 12);
  const user = await User.create({ name, email, phone, passwordHash, role });
  return { user: sanitize(user), ...issueTokens(user) };
};

exports.login = async ({ email, phone, password }) => {
  const user = await User.findOne(email ? { email } : { phone }).select('+passwordHash');
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

function sanitize(user) {
  const { _id, name, email, phone, role, avatarUrl, language } = user;
  return { id: _id, name, email, phone, role, avatarUrl, language };
}

// --- Phase 2: Firebase token exchange ---
// Client signs in with Firebase (phone OTP / Google / Apple / email),
// sends the Firebase ID token here, receives our JWT pair.
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
    // First login → create account. Role only settable at creation,
    // and never an admin role via this endpoint.
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
  return { user: sanitize(user), ...issueTokens(user), isNewUser: !user.createdAt || user.createdAt.getTime() > Date.now() - 5000 };
};
