const mongoose = require('mongoose');

const reviewSchema = new mongoose.Schema(
  {
    customer: { type: mongoose.Types.ObjectId, ref: 'User', required: true, index: true },
    business: { type: mongoose.Types.ObjectId, ref: 'Business', required: true, index: true },
    product: { type: mongoose.Types.ObjectId, ref: 'Product', index: true },
    order: { type: mongoose.Types.ObjectId, ref: 'Order' }, // presence = verified purchase
    rating: { type: Number, min: 1, max: 5, required: true },
    comment: { type: String, maxlength: 1000 },
    images: [String],
    reply: { text: String, at: Date }, // entrepreneur response
    isVerifiedPurchase: { type: Boolean, default: false },
    isFlagged: { type: Boolean, default: false }, // trust-AI flag (Phase 13)
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

// One review per customer per product per order
reviewSchema.index({ customer: 1, product: 1, order: 1 }, { unique: true, sparse: true });

module.exports = mongoose.model('Review', reviewSchema);
