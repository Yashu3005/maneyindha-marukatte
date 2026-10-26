const mongoose = require('mongoose');

// One live code per (email, purpose). Issuing a new code overwrites the previous one,
// which is how earlier codes are superseded. The code itself is never stored — only an
// HMAC of it — and MongoDB's TTL index removes expired rows automatically.
const otpTokenSchema = new mongoose.Schema(
  {
    email: { type: String, required: true, lowercase: true, trim: true },
    purpose: { type: String, required: true, default: 'login' },
    codeHash: { type: String, required: true },
    expiresAt: { type: Date, required: true },
    attempts: { type: Number, default: 0 },
    lastSentAt: { type: Date, required: true },
    consumedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

otpTokenSchema.index({ email: 1, purpose: 1 }, { unique: true });
// Keep the row for an hour past expiry so the resend cooldown survives, then purge.
otpTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 3600 });

module.exports = mongoose.model('OtpToken', otpTokenSchema);
