const mongoose = require('mongoose');

const wishlistSchema = new mongoose.Schema(
  {
    customer: { type: mongoose.Types.ObjectId, ref: 'User', required: true, unique: true },
    products: [{ type: mongoose.Types.ObjectId, ref: 'Product' }],
    businesses: [{ type: mongoose.Types.ObjectId, ref: 'Business' }], // favourite shops
  },
  { timestamps: true }
);

module.exports = mongoose.model('Wishlist', wishlistSchema);
