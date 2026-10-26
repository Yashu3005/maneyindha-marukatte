const mongoose = require('mongoose');

// A server-side record behind every refresh token. Deleting it (logout) makes the
// refresh token unusable immediately; access tokens then lapse within their short TTL.
const refreshSessionSchema = new mongoose.Schema(
  {
    sid: { type: String, required: true, unique: true },
    user: { type: mongoose.Types.ObjectId, ref: 'User', required: true, index: true },
    expiresAt: { type: Date, required: true },
  },
  { timestamps: true }
);

refreshSessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('RefreshSession', refreshSessionSchema);
