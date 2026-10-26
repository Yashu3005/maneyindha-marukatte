const mongoose = require('mongoose');

const otpSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    hashedOtp: {
      type: String,
      required: true,
    },
    purpose: {
      type: String,
      enum: ['registration', 'login', 'verification'],
      default: 'verification',
      index: true,
    },
    attempts: {
      type: Number,
      default: 0,
      min: 0,
    },
    isConsumed: {
      type: Boolean,
      default: false,
    },
    lastResendAt: {
      type: Date,
      default: Date.now,
    },
    expiresAt: {
      type: Date,
      required: true,
      index: { expires: 0 }, // TTL index: MongoDB automatically deletes documents when expiresAt is reached
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Otp', otpSchema);
