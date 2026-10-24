const mongoose = require('mongoose');

const productSchema = new mongoose.Schema(
  {
    business: { type: mongoose.Types.ObjectId, ref: 'Business', required: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 150 },
    description: { type: String, maxlength: 3000 },
    category: { type: mongoose.Types.ObjectId, ref: 'Category', index: true },
    images: [String],
    videoUrl: String,
    price: { type: Number, required: true, min: 0 },
    mrp: { type: Number, min: 0 },
    variants: [{ name: String, price: Number, stock: Number, sku: String }],
    stock: { type: Number, default: 0, min: 0 },
    lowStockThreshold: { type: Number, default: 5 },
    isCustomOrder: { type: Boolean, default: false },
    tags: [String],
    specifications: [{ key: String, value: String }],
    customizations: [
      {
        label: String,
        fieldType: { type: String, enum: ['text', 'select', 'radio'], default: 'text' },
        options: [String],
        required: { type: Boolean, default: false },
      },
    ],
    deliveryOptions: {
      homeDelivery: { type: Boolean, default: true },
      pickup: { type: Boolean, default: true },
      deliveryRadius: { type: Number, default: 5 },
      deliveryCharge: { type: Number, default: 30 },
      freeDelivery: { type: Boolean, default: false },
      estimatedDelivery: { type: String, default: 'Today before 5:30 PM' },
    },
    afterSales: {
      supportType: {
        type: String,
        enum: ['not_available', 'replacement_only', 'return_and_replacement'],
        default: 'not_available',
      },
      supportWindow: { type: String, default: '3 Days' },
      returnRequired: { type: Boolean, default: false },
      returnInstructions: String,
    },
    moderation: {
      status: {
        type: String,
        enum: ['active', 'reported', 'hidden', 'removed'],
        default: 'active',
        index: true,
      },
      reportCount: { type: Number, default: 0 },
      reports: [
        {
          customer: { type: mongoose.Types.ObjectId, ref: 'User' },
          reason: String,
          description: String,
          createdAt: { type: Date, default: Date.now },
        },
      ],
      adminReason: String,
    },
    ordersCount: { type: Number, default: 0 },
    viewsCount: { type: Number, default: 0 },
    rating: { avg: { type: Number, default: 0 }, count: { type: Number, default: 0 } },
    isActive: { type: Boolean, default: true },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

productSchema.index({ name: 'text', description: 'text', tags: 'text' });
productSchema.index({ business: 1, isActive: 1 });

module.exports = mongoose.model('Product', productSchema);
