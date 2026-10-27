// Shared test helpers. Secrets here are throwaway values for the test process only.
process.env.JWT_SECRET = 'test-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh';

const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');

exports.oid = () => new mongoose.Types.ObjectId();
exports.tokenFor = (role, id = new mongoose.Types.ObjectId().toString(), opts = {}) =>
  jwt.sign({ id, role }, process.env.JWT_SECRET, { expiresIn: '15m', ...opts });
exports.bearer = (role, id) => ({ Authorization: `Bearer ${exports.tokenFor(role, id)}` });

// The admin area needs the one configured administrator. This sets that up for a test: ADMIN_USERNAME plus a
// User.findById stand-in that knows the admin id (and returns nobody else).
exports.ADMIN = { id: '64b7f0f0f0f0f0f0f0f0f0f0', username: 'the-admin' };
exports.installAdmin = (UserModel, { username = exports.ADMIN.username, role = 'admin', isActive = true } = {}) => {
  process.env.ADMIN_USERNAME = exports.ADMIN.username;
  return jest.spyOn(UserModel, 'findById').mockImplementation((id) => ({
    select: async () => (String(id) === exports.ADMIN.id ? { _id: id, role, isActive, username } : null),
  }));
};
exports.adminBearer = () => exports.bearer('admin', exports.ADMIN.id);
