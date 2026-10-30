const mongoose = require('mongoose');

const ROLES = ['customer', 'entrepreneur', 'delivery_partner', 'admin', 'super_admin'];

const userSchema = new mongoose.Schema(
  {
    firebaseUid: { type: String, index: true, sparse: true },
    name: { type: String, required: true, trim: true, maxlength: 100 },
    email: { type: String, lowercase: true, trim: true, index: true, sparse: true },
    phone: { type: String, trim: true, index: true, sparse: true },
    passwordHash: { type: String, select: false },
    role: { type: String, enum: ROLES, default: 'customer', index: true },
    username: { type: String, trim: true, lowercase: true, unique: true, sparse: true },
    emailVerified: { type: Boolean, default: false },
    profileComplete: { type: Boolean, default: false },
    securityQuestions: { type: mongoose.Schema.Types.Mixed, select: false },
    bankAccount: { type: mongoose.Schema.Types.Mixed },
    avatarUrl: String,
    language: { type: String, default: 'en' },
    addresses: [
      {
        label: String,
        line1: String,
        line2: String,
        city: String,
        state: String,
        pincode: String,
        location: {
          type: { type: String, enum: ['Point'] },
          coordinates: { type: [Number], default: undefined }, // [lng, lat]; absent unless the user shared a location
        },
      },
    ],
    fcmTokens: [String],
    isActive: { type: Boolean, default: true },
    suspension: { reason: { type: String, maxlength: 300 }, at: Date },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

userSchema.index({ 'addresses.location': '2dsphere' });

module.exports = mongoose.model('User', userSchema);
module.exports.ROLES = ROLES;
