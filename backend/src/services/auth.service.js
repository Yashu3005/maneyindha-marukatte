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
