const mongoose = require('mongoose');

// One row per processed Razorpay webhook event (X-Razorpay-Event-Id). The unique index is the
// idempotency guard: a redelivered event fails to insert and is acknowledged without re-processing.
const paymentEventSchema = new mongoose.Schema(
  {
    eventId: { type: String, required: true, unique: true },
    type: String,
    order: { type: mongoose.Types.ObjectId, ref: 'Order' },
  },
  { timestamps: true }
);
paymentEventSchema.index({ createdAt: 1 }, { expireAfterSeconds: 90 * 24 * 3600 });

module.exports = mongoose.model('PaymentEvent', paymentEventSchema);
