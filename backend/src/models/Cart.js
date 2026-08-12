const mongoose = require('mongoose');

const cartSchema = new mongoose.Schema(
  {
    customer: { type: mongoose.Types.ObjectId, ref: 'User', required: true, unique: true },
    business: { type: mongoose.Types.ObjectId, ref: 'Business' }, // one business per cart (like Swiggy)
    items: [
      {
        product: { type: mongoose.Types.ObjectId, ref: 'Product', required: true },
        variant: String,
        quantity: { type: Number, min: 1, default: 1 },
      },
    ],
    coupon: String,
  },
  { timestamps: true }
);

module.exports = mongoose.model('Cart', cartSchema);
