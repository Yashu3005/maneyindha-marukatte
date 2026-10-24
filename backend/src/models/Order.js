const mongoose = require('mongoose');

// Order state machine — transitions enforced in services/orderService.js
const STATUSES = [
  'pending', 'confirmed', 'preparing', 'ready', 'assigned',
  'picked_up', 'out_for_delivery', 'delivered',
  'cancelled', 'rejected', 'refunded', 'payment_failed',
];

const VALID_TRANSITIONS = {
  pending: ['confirmed', 'rejected', 'cancelled', 'payment_failed'],
  confirmed: ['preparing', 'cancelled'],
  preparing: ['ready', 'cancelled'],
  ready: ['assigned', 'picked_up'],
  assigned: ['picked_up'],
  picked_up: ['out_for_delivery'],
  out_for_delivery: ['delivered'],
  delivered: ['refunded'],
  cancelled: ['refunded'],
  rejected: ['refunded'],
};

const orderSchema = new mongoose.Schema(
  {
    orderNumber: { type: String, unique: true, index: true },
    customer: { type: mongoose.Types.ObjectId, ref: 'User', required: true, index: true },
    business: { type: mongoose.Types.ObjectId, ref: 'Business', required: true, index: true },
    deliveryPartner: { type: mongoose.Types.ObjectId, ref: 'User', index: true },
    items: [
      {
        product: { type: mongoose.Types.ObjectId, ref: 'Product', required: true },
        name: String,          // snapshot at order time
        variant: String,
        customization: String, // snapshot of customized field at order time
        unitPrice: Number,     // snapshot at order time
        quantity: { type: Number, min: 1 },
      },
    ],
    amounts: {
      subtotal: Number,
      deliveryFee: Number,
      discount: Number,
      tax: Number,
      total: Number,
    },
    coupon: { code: String, discount: Number },
    status: { type: String, enum: STATUSES, default: 'pending', index: true },
    statusHistory: [{ status: String, at: Date, by: { type: mongoose.Types.ObjectId, ref: 'User' } }],
    payment: {
      method: { type: String, enum: ['razorpay', 'upi', 'card', 'wallet', 'cod'], default: 'cod' },
      razorpayOrderId: String,
      razorpayPaymentId: String,
      status: { type: String, enum: ['pending', 'paid', 'failed', 'refunded', 'refund_in_progress', 'refund_completed'], default: 'pending' },
    },
    deliveryAddress: {
      label: String,
      line1: String,
      city: String,
      pincode: String,
      location: { type: { type: String, enum: ['Point'], default: 'Point' }, coordinates: [Number] },
    },
    deliveryOtp: { type: String, select: false },
    isSelfPickup: { type: Boolean, default: false },
    notes: String,

    // After-Sales support request (Refund or Replacement)
    afterSales: {
      isRequested: { type: Boolean, default: false },
      type: { type: String, enum: ['refund', 'replacement'] },
      reason: String,
      description: String,
      images: [String],
      requestedAt: Date,
      status: {
        type: String,
        enum: [
          'none',
          'requested',
          'in_review',
          'approved',
          'rejected',
          'return_required',
          'return_initiated',
          'return_received',
          'replacement_shipped',
          'replacement_delivered',
          'refund_completed',
        ],
        default: 'none',
      },
      returnRequired: { type: Boolean, default: false },
      returnStatus: { type: String, enum: ['none', 'return_required', 'return_initiated', 'return_received'], default: 'none' },
      entrepreneurDecision: String,
      rejectionReason: String,
      aiSuggestion: String,
      decidedAt: Date,
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Order', orderSchema);
module.exports.STATUSES = STATUSES;
module.exports.VALID_TRANSITIONS = VALID_TRANSITIONS;
