const User = require('../models/User');
const RefreshSession = require('../models/RefreshSession');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');
const { verifyPassword, safeEqual } = require('../utils/adminPassword');
const authService = require('./auth.service');

const ADMIN_ROLES = ['admin', 'super_admin'];

const adminUsername = () => String(process.env.ADMIN_USERNAME || '').trim().toLowerCase();
exports.adminUsername = adminUsername;
exports.isConfigured = () => !!(adminUsername() && process.env.ADMIN_PASSWORD_HASH);

// Dummy hash so an unknown username costs the same time as a wrong password.
const DUMMY = 'scrypt:16384:AAAAAAAAAAAAAAAAAAAAAA:' + 'A'.repeat(86);

/**
 * The one and only way to become an administrator. The credentials live in server
 * configuration (ADMIN_USERNAME + ADMIN_PASSWORD_HASH), not in the database, so there is
 * no sign-up, no OTP and no profile call that can create a second admin.
 */
exports.login = async ({ username, password }) => {
  if (!exports.isConfigured()) {
    throw new AppError('Admin sign-in is not set up on this server', 503, 'ADMIN_NOT_CONFIGURED');
  }
  const nameOk = safeEqual(String(username || '').trim().toLowerCase(), adminUsername());
  const passOk = await verifyPassword(String(password || ''), nameOk ? process.env.ADMIN_PASSWORD_HASH : DUMMY);
  if (!nameOk || !passOk) {
    logger.warn('Failed admin sign-in attempt');
    throw new AppError('Invalid credentials', 401);
  }

  const uname = adminUsername();
  let admin = await User.findOne({ username: uname });
  if (admin && !ADMIN_ROLES.includes(admin.role)) {
    // A normal member already holds this username. Never promote them: that would hand admin to someone
    // who only knows their own password.
    throw new AppError('This username is reserved. Choose another ADMIN_USERNAME.', 409, 'ADMIN_USERNAME_TAKEN');
  }
  if (!admin) {
    admin = new User({
      name: 'Administrator', username: uname, role: 'admin',
      emailVerified: true, profileComplete: true, isActive: true,
    });
  }
  admin.role = 'admin';
  admin.isActive = true;
  await admin.save();
  // The database never holds an admin password (clears one left over from an older setup).
  await User.updateOne({ _id: admin._id }, { $unset: { passwordHash: 1 } });

  // Exactly one admin: anyone else carrying an admin role (from an older setup) is demoted and signed out.
  const others = await User.find({ role: { $in: ADMIN_ROLES }, _id: { $ne: admin._id } }).select('_id');
  if (others.length) {
    const ids = others.map((u) => u._id);
    await User.updateMany({ _id: { $in: ids } }, { $set: { role: 'customer' } });
    await RefreshSession.deleteMany({ user: { $in: ids } });
    logger.warn(`Demoted ${ids.length} extra admin account(s)`);
  }

  return { user: authService.sanitize(admin), ...(await authService.issueSession(admin)) };
};

/** True only for the one configured administrator account. */
exports.isTheAdmin = (user) =>
  !!user && user.isActive !== false && ADMIN_ROLES.includes(user.role)
  && !!adminUsername() && String(user.username || '').toLowerCase() === adminUsername();
