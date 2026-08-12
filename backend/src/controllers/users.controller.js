const bcrypt = require('bcryptjs');
const User = require('../models/User');
const AppError = require('../utils/AppError');
const { ok } = require('../utils/apiResponse');
const { issueTokens, sanitize } = require('../services/auth.service');

exports.me = async (req, res, next) => {
  try {
    const user = await User.findById(req.user.id);
    if (!user) throw new AppError('User not found', 404);
    ok(res, sanitize(user));
  } catch (e) { next(e); }
};

exports.updateMe = async (req, res, next) => {
  try {
    const allowed = ['name', 'phone', 'avatarUrl', 'language', 'addresses', 'bankAccount'];
    const updates = {};
    for (const key of allowed) {
      if (req.body[key] !== undefined) updates[key] = req.body[key];
    }
    const user = await User.findById(req.user.id);
    if (!user) throw new AppError('User not found', 404);
    Object.assign(user, updates);
    if (user.name && user.name !== 'New Member' && user.phone) user.profileComplete = true;
    await user.save();
    ok(res, sanitize(user));
  } catch (e) { next(e); }
};

// Easy role switch: customer <-> entrepreneur (spec: changeable from profile).
// Returns fresh tokens because role lives inside the JWT.
exports.switchRole = async (req, res, next) => {
  try {
    const { role } = req.body;
    if (!['customer', 'entrepreneur'].includes(role)) {
      throw new AppError('role must be customer or entrepreneur', 422);
    }
    const user = await User.findById(req.user.id);
    if (!user) throw new AppError('User not found', 404);
    user.role = role;
    await user.save();
    // Tell the client whether a business already exists so returning
    // entrepreneurs skip onboarding — decided server-side, no race.
    const Business = require('../models/Business');
    const hasBusiness = role === 'entrepreneur'
      ? !!(await Business.exists({ owner: user._id, isActive: true }))
      : false;
    ok(res, { user: sanitize(user), ...issueTokens(user), hasBusiness });
  } catch (e) { next(e); }
};

// Set (or change) username + password
exports.setCredentials = async (req, res, next) => {
  try {
    const { username, password } = req.body;
    if (!password || password.length < 6) throw new AppError('Password must be at least 6 characters', 422);
    const user = await User.findById(req.user.id);
    if (!user) throw new AppError('User not found', 404);
    if (username) {
      const clash = await User.findOne({ username: username.toLowerCase(), _id: { $ne: user._id } });
      if (clash) throw new AppError('Username already taken', 409);
      user.username = username.toLowerCase();
    }
    user.passwordHash = await bcrypt.hash(password, 12);
    await user.save();
    ok(res, sanitize(user));
  } catch (e) { next(e); }
};

// MVP storage; hash answers like passwords before production.
exports.setSecurityQuestions = async (req, res, next) => {
  try {
    const { answers } = req.body;
    if (!answers || typeof answers !== 'object') throw new AppError('answers object required', 422);
    const user = await User.findById(req.user.id);
    if (!user) throw new AppError('User not found', 404);
    user.securityQuestions = answers;
    await user.save();
    ok(res, { saved: true });
  } catch (e) { next(e); }
};
