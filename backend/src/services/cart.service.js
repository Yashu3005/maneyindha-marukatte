const Cart = require('../models/Cart');
const Product = require('../models/Product');
const Coupon = require('../models/Coupon');
const Order = require('../models/Order');
const AppError = require('../utils/AppError');

exports.getCart = async (customerId) => {
  const cart = await Cart.findOne({ customer: customerId })
    .populate('items.product', 'name price images stock isActive')
    .populate('business', 'name isOpen');
  if (!cart) return { items: [], totals: { subtotal: 0 } };
  return withTotals(cart);
};

exports.addItem = async (customerId, { productId, quantity = 1, variant }) => {
  const product = await Product.findOne({ _id: productId, isActive: true });
  if (!product) throw new AppError('Product not found', 404);
  if (product.stock < quantity) throw new AppError('Insufficient stock', 422);

  let cart = await Cart.findOne({ customer: customerId });

  // One business per cart — adding from a different business replaces the cart.
  if (cart && cart.business && String(cart.business) !== String(product.business)) {
    cart.items = [];
    cart.coupon = undefined;
  }
  if (!cart) cart = new Cart({ customer: customerId, items: [] });

  cart.business = product.business;
  const existing = cart.items.find(
    (i) => String(i.product) === String(productId) && (i.variant || '') === (variant || '')
  );
  if (existing) existing.quantity += quantity;
  else cart.items.push({ product: productId, quantity, variant });

  await cart.save();
  return exports.getCart(customerId);
};

exports.updateItem = async (customerId, { productId, quantity, variant }) => {
  const cart = await Cart.findOne({ customer: customerId });
  if (!cart) throw new AppError('Cart is empty', 404);

  const idx = cart.items.findIndex(
    (i) => String(i.product) === String(productId) && (i.variant || '') === (variant || '')
  );
  if (idx === -1) throw new AppError('Item not in cart', 404);

  if (quantity <= 0) cart.items.splice(idx, 1);
  else cart.items[idx].quantity = quantity;

  if (cart.items.length === 0) { cart.business = undefined; cart.coupon = undefined; }
  await cart.save();
  return exports.getCart(customerId);
};

exports.clearCart = async (customerId) => {
  await Cart.findOneAndUpdate({ customer: customerId }, { items: [], business: undefined, coupon: undefined });
  return { items: [], totals: { subtotal: 0 } };
};

exports.applyCoupon = async (customerId, code) => {
  const cart = await Cart.findOne({ customer: customerId }).populate('items.product', 'price');
  if (!cart || !cart.items.length) throw new AppError('Cart is empty', 422);

  const subtotal = cart.items.reduce((s, i) => s + (i.product?.price || 0) * i.quantity, 0);
  await exports.validateCoupon(code, { businessId: cart.business, subtotal, customerId });

  cart.coupon = code.toUpperCase();
  await cart.save();
  return exports.getCart(customerId);
};

// Shared validation — also used at checkout so a coupon can't go stale in the cart.
exports.validateCoupon = async (code, { businessId, subtotal, customerId }) => {
  const coupon = await Coupon.findOne({ code: code.toUpperCase(), isActive: true });
  if (!coupon) throw new AppError('Invalid coupon', 422);

  const now = new Date();
  if (coupon.validFrom && now < coupon.validFrom) throw new AppError('Coupon not yet active', 422);
  if (coupon.validUntil && now > coupon.validUntil) throw new AppError('Coupon expired', 422);
  if (coupon.business && String(coupon.business) !== String(businessId)) {
    throw new AppError('Coupon not valid for this shop', 422);
  }
  if (subtotal < coupon.minOrderAmount) {
    throw new AppError(`Minimum order amount is ${coupon.minOrderAmount}`, 422);
  }
  if (coupon.usageLimitTotal && coupon.usedCount >= coupon.usageLimitTotal) {
    throw new AppError('Coupon usage limit reached', 422);
  }
  if (coupon.usageLimitPerUser && customerId) {
    const used = await Order.countDocuments({
      customer: customerId,
      'coupon.code': coupon.code,
      status: { $nin: ['cancelled', 'rejected', 'payment_failed'] },
    });
    if (used >= coupon.usageLimitPerUser) throw new AppError('You have already used this coupon', 422);
  }

  return coupon;
};

exports.computeDiscount = (coupon, subtotal) => {
  let discount = coupon.type === 'percent' ? (subtotal * coupon.value) / 100 : coupon.value;
  if (coupon.maxDiscount) discount = Math.min(discount, coupon.maxDiscount);
  return Math.min(Math.round(discount), subtotal);
};

async function withTotals(cart) {
  const subtotal = cart.items.reduce((s, i) => s + (i.product?.price || 0) * i.quantity, 0);
  let discount = 0;
  if (cart.coupon) {
    try {
      const coupon = await exports.validateCoupon(cart.coupon, {
        businessId: cart.business, subtotal, customerId: cart.customer,
      });
      discount = exports.computeDiscount(coupon, subtotal);
    } catch { discount = 0; } // stale coupon → show no discount, checkout will strip it
  }
  return { ...cart.toObject(), totals: { subtotal, discount, total: subtotal - discount } };
}
