const mongoose = require('mongoose');

const businessSchema = new mongoose.Schema(
  {
    owner: { type: mongoose.Types.ObjectId, ref: 'User', required: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    slug: { type: String, unique: true, index: true },
    description: { type: String, maxlength: 2000 },
    category: { type: mongoose.Types.ObjectId, ref: 'Category', index: true },
    logoUrl: String,
    bannerUrl: String,
    gallery: [String],
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], required: true }, // [lng, lat]
    },
    address: { line1: String, city: String, state: String, pincode: String },
    workingHours: [{ day: Number, open: String, close: String, closed: Boolean }],
    gstNumber: String,
    yearsOfExperience: String,
    verification: {
      status: { type: String, enum: ['pending', 'in_review', 'approved', 'rejected'], default: 'pending', index: true },
      documents: [{ type: { type: String }, url: String, identityType: String, uploadedAt: Date }],
      reviewedBy: { type: mongoose.Types.ObjectId, ref: 'User' },
      reviewedAt: Date,
      rejectionReason: String,
    },
    rating: { avg: { type: Number, default: 0 }, count: { type: Number, default: 0 } },
    followerCount: { type: Number, default: 0 },
    isOpen: { type: Boolean, default: true },
    isActive: { type: Boolean, default: true },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

businessSchema.index({ location: '2dsphere' });
businessSchema.index({ name: 'text', description: 'text' });

module.exports = mongoose.model('Business', businessSchema);
