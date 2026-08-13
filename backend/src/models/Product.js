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
    rating: { avg: { type: Number, default: 0 }, count: { type: Number, default: 0 } },
    isActive: { type: Boolean, default: true },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

productSchema.index({ name: 'text', description: 'text', tags: 'text' });
productSchema.index({ business: 1, isActive: 1 });

module.exports = mongoose.model('Product', productSchema);
