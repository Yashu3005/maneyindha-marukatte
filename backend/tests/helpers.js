// Shared test helpers. Secrets here are throwaway values for the test process only.
process.env.JWT_SECRET = 'test-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh';

const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');

exports.oid = () => new mongoose.Types.ObjectId();
exports.tokenFor = (role, id = new mongoose.Types.ObjectId().toString(), opts = {}) =>
  jwt.sign({ id, role }, process.env.JWT_SECRET, { expiresIn: '15m', ...opts });
exports.bearer = (role, id) => ({ Authorization: `Bearer ${exports.tokenFor(role, id)}` });
