const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Types.ObjectId, ref: 'User', required: true, index: true },
    type: {
      type: String,
      enum: ['order', 'payment', 'refund', 'message', 'review', 'promotion', 'verification', 'delivery', 'reward', 'system'],
      required: true,
    },
    title: { type: String, required: true },
    body: String,
    data: mongoose.Schema.Types.Mixed, // deep-link payload
    isRead: { type: Boolean, default: false, index: true },
  },
  { timestamps: true }
);

notificationSchema.index({ user: 1, createdAt: -1 });

module.exports = mongoose.model('Notification', notificationSchema);
