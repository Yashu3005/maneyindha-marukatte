const mongoose = require('mongoose');

const supportTicketSchema = new mongoose.Schema(
  {
    ticketNumber: { type: String, unique: true, index: true },
    customer: { type: mongoose.Types.ObjectId, ref: 'User', required: true, index: true },
    issueType: {
      type: String,
      enum: [
        'Account Issue',
        'Payment Issue',
        'Order Issue',
        'Refund Appeal',
        'Replacement Appeal',
        'Other Issue',
      ],
      required: true,
    },
    description: { type: String, required: true },
    attachments: [String],
    order: { type: mongoose.Types.ObjectId, ref: 'Order' },
    status: {
      type: String,
      enum: ['open', 'in_progress', 'resolved', 'closed'],
      default: 'open',
      index: true,
    },
    adminNotes: String,
    resolvedBy: { type: mongoose.Types.ObjectId, ref: 'User' },
    resolvedAt: Date,
  },
  { timestamps: true }
);

module.exports = mongoose.model('SupportTicket', supportTicketSchema);
