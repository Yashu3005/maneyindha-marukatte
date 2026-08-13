const mongoose = require('mongoose');

const transactionSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Types.ObjectId, ref: 'User', required: true, index: true },
    order: { type: mongoose.Types.ObjectId, ref: 'Order', index: true },
    type: { type: String, enum: ['payment', 'refund', 'payout', 'wallet_credit', 'wallet_debit', 'reward'], required: true },
    amount: { type: Number, required: true },
    currency: { type: String, default: 'INR' },
    gateway: { type: String, enum: ['razorpay', 'wallet', 'cod', 'internal'] },
    gatewayRef: String, // razorpay payment/refund id
    status: { type: String, enum: ['pending', 'success', 'failed'], default: 'pending', index: true },
    meta: mongoose.Schema.Types.Mixed,
  },
  { timestamps: true }
);

module.exports = mongoose.model('Transaction', transactionSchema);
