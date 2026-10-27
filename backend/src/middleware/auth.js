const jwt = require('jsonwebtoken');
const AppError = require('../utils/AppError');

function readToken(req) {
  const header = req.headers.authorization || '';
  return header.startsWith('Bearer ') ? header.slice(7) : null;
}

// Verifies the access token and attaches { id, role } to req.user.
exports.requireAuth = (req, _res, next) => {
  const token = readToken(req);
  if (!token) return next(new AppError('Authentication required', 401));
  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch {
    next(new AppError('Invalid or expired token', 401));
  }
};

// For public endpoints whose output depends on who is asking (e.g. an owner may
// see their own unapproved shop). A missing/invalid token simply means anonymous.
exports.optionalAuth = (req, _res, next) => {
  const token = readToken(req);
  if (token) {
    try { req.user = jwt.verify(token, process.env.JWT_SECRET); } catch { /* anonymous */ }
  }
  next();
};

// Role-based access control. Usage: requireRole('admin', 'super_admin')
exports.requireRole = (...roles) => (req, _res, next) => {
  if (!req.user || !roles.includes(req.user.role)) {
    return next(new AppError('Forbidden', 403));
  }
  next();
};

// The admin area: a valid token AND the one configured administrator account. The role in the token alone is
// not enough, so a stale or forged-by-mistake admin role elsewhere in the data can never open it.
exports.requireAdmin = [
  exports.requireAuth,
  async (req, _res, next) => {
    try {
      // Cheap check first: a token that does not even claim an admin role never reaches the database.
      if (!['admin', 'super_admin'].includes(req.user.role)) return next(new AppError('Forbidden', 403));
      const User = require('../models/User');
      const { isTheAdmin } = require('../services/adminAuth.service');
      const user = await User.findById(req.user.id).select('role isActive username');
      if (!isTheAdmin(user)) return next(new AppError('Forbidden', 403));
      next();
    } catch (e) { next(e); }
  },
];
