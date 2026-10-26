const mongoose = require('mongoose');

const couponSchema = new mongoose.Schema(
  {
    code: { type: String, required: true, unique: true, uppercase: true, trim: true },
    business: { type: mongoose.Types.ObjectId, ref: 'Business', index: true }, // null = platform-wide
    type: { type: String, enum: ['percent', 'flat'], required: true },
    value: { type: Number, required: true, min: 0 },
    maxDiscount: Number,          // cap for percent coupons
    minOrderAmount: { type: Number, default: 0 },
    usageLimitTotal: Number,
    usageLimitPerUser: { type: Number, default: 1 },
    usedCount: { type: Number, default: 0 },
    validFrom: Date,
    validUntil: Date,
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Coupon', couponSchema);
