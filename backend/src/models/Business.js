const mongoose = require('mongoose');

const { isValidLatLng, coarsen } = require('../utils/geo');

const coordValidator = {
  validator: (v) => v == null || (v.length === 2 && isValidLatLng(v[1], v[0])),
  message: 'coordinates must be a real [lng, lat] pair',
};

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
    // Exact point — visible to the owner and admins only. Absent until the owner sets it (never a made-up default).
    location: {
      type: { type: String, enum: ['Point'] },
      coordinates: { type: [Number], default: undefined, validate: coordValidator }, // [lng, lat]
    },
    // Coarsened copy (≈110 m) used for public discovery; derived from `location`, never client-supplied.
    publicLocation: {
      type: { type: String, enum: ['Point'] },
      coordinates: { type: [Number], default: undefined, validate: coordValidator },
    },
    locationSource: { type: String, enum: ['device', 'manual', 'unset'], default: 'unset' },
    address: { line1: String, city: String, state: String, pincode: String },
    workingHours: [{ day: Number, open: String, close: String, closed: Boolean }],
    gstNumber: String,
    yearsOfExperience: String,
    verification: {
      status: { type: String, enum: ['pending', 'in_review', 'approved', 'rejected'], default: 'pending', index: true },
      documents: [{
        type: { type: String }, url: String, identityType: String, uploadedAt: Date,
        // Private uploads: stored as authenticated assets, never as a public URL. Admins get a short-lived link.
        publicId: String, resourceType: String, format: String, mime: String, bytes: Number, originalName: String,
      }],
      reviewedBy: { type: mongoose.Types.ObjectId, ref: 'User' },
      reviewedAt: Date,
      rejectionReason: String,
    },
    // "Story" video the owner shows customers when they open the shop (hosted on Cloudinary; uploaded directly from the browser).
    promoVideo: {
      publicId: String, url: String, posterUrl: String,
      duration: Number, bytes: Number, format: String,
      title: { type: String, maxlength: 80 }, caption: { type: String, maxlength: 240 },
      uploadedAt: Date,
    },
    rating: { avg: { type: Number, default: 0 }, count: { type: Number, default: 0 } },
    followerCount: { type: Number, default: 0 },
    isOpen: { type: Boolean, default: true },
    isActive: { type: Boolean, default: true },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

// Keep the public point in step with the exact one, whichever way the document is saved.
businessSchema.pre('validate', function syncPublicLocation(next) {
  const c = this.location?.coordinates;
  if (c?.length === 2) {
    this.location.type = 'Point';
    this.publicLocation = { type: 'Point', coordinates: coarsen(c) };
  }
  next();
});

businessSchema.index({ publicLocation: '2dsphere' }); // discovery runs on the coarsened point only
businessSchema.index({ name: 'text', description: 'text' });

module.exports = mongoose.model('Business', businessSchema);
