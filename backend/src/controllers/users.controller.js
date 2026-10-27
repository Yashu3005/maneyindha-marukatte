const bcrypt = require('bcryptjs');
const User = require('../models/User');
const AppError = require('../utils/AppError');
const { ok } = require('../utils/apiResponse');
const { issueSession, sanitize } = require('../services/auth.service');
const avatarService = require('../services/avatar.service');

exports.me = async (req, res, next) => {
  try {
    const user = await User.findById(req.user.id);
    if (!user) throw new AppError('User not found', 404);
    ok(res, sanitize(user));
  } catch (e) { next(e); }
};

exports.updateMe = async (req, res, next) => {
  try {
    // avatarUrl is deliberately NOT editable here: it is only ever set by the validated upload endpoint.
    const allowed = ['name', 'phone', 'language', 'addresses', 'bankAccount'];
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

exports.uploadAvatar = async (req, res, next) => {
  try { ok(res, sanitize(await avatarService.setAvatar(req.user.id, req.file))); }
  catch (e) { next(e); }
};

exports.deleteAvatar = async (req, res, next) => {
  try { ok(res, sanitize(await avatarService.removeAvatar(req.user.id))); }
  catch (e) { next(e); }
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
    // Only the customer <-> entrepreneur toggle is self-service. Without this guard an
    // admin (or delivery partner) calling this endpoint would silently lose their role.
    if (!['customer', 'entrepreneur'].includes(user.role)) {
      throw new AppError('This account type cannot switch roles', 403);
    }
    user.role = role;
    await user.save();
    // Tell the client whether a business already exists so returning
    // entrepreneurs skip onboarding — decided server-side, no race.
    const Business = require('../models/Business');
    const hasBusiness = role === 'entrepreneur'
      ? !!(await Business.exists({ owner: user._id, isActive: true }))
      : false;
    ok(res, { user: sanitize(user), ...(await issueSession(user, req.user.sid)), hasBusiness });
  } catch (e) { next(e); }
};

// Set (or change) username + password
exports.setCredentials = async (req, res, next) => {
  try {
    const { username, password } = req.body;
    if (typeof password !== 'string' || password.length < 6 || password.length > 128) {
      throw new AppError('Password must be 6-128 characters', 422);
    }
    if (username !== undefined && username !== null && (typeof username !== 'string' || username.length > 50)) {
      throw new AppError('Invalid username', 422);
    }
    const user = await User.findById(req.user.id);
    if (!user) throw new AppError('User not found', 404);
    if (username) {
      // The administrator's username is reserved: nobody else may take it.
      if (username.trim().toLowerCase() === require('../services/adminAuth.service').adminUsername()) {
        throw new AppError('Username already taken', 409);
      }
      const clash = await User.findOne({ username: username.toLowerCase(), _id: { $ne: user._id } });
      if (clash) throw new AppError('Username already taken', 409);
      user.username = username.toLowerCase();
    }
    user.passwordHash = await bcrypt.hash(password, 12);
    await user.save();
    ok(res, sanitize(user));
  } catch (e) { next(e); }
};

// Answers are hashed (like passwords) and compared case-insensitively.
exports.setSecurityQuestions = async (req, res, next) => {
  try {
    const { answers } = req.body;
    if (!answers || typeof answers !== 'object' || Array.isArray(answers)) {
      throw new AppError('answers object required', 422);
    }
    const entries = Object.entries(answers);
    if (!entries.length || entries.length > 10 ||
        entries.some(([k, v]) => k.length > 100 || typeof v !== 'string' || !v.trim() || v.length > 200)) {
      throw new AppError('answers must be 1-10 non-empty text answers', 422);
    }
    const user = await User.findById(req.user.id);
    if (!user) throw new AppError('User not found', 404);
    const hashed = {};
    for (const [question, answer] of entries) {
      hashed[question] = await bcrypt.hash(answer.trim().toLowerCase(), 10);
    }
    user.securityQuestions = hashed;
    await user.save();
    ok(res, { saved: true });
  } catch (e) { next(e); }
};
