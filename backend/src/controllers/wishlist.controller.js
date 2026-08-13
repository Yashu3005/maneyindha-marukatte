const Wishlist = require('../models/Wishlist');
const { ok } = require('../utils/apiResponse');

exports.get = async (req, res, next) => {
  try {
    const wl = await Wishlist.findOne({ customer: req.user.id })
      .populate('products', 'name price images rating')
      .populate('businesses', 'name logoUrl rating');
    ok(res, wl || { products: [], businesses: [] });
  } catch (e) { next(e); }
};

exports.toggleProduct = async (req, res, next) => {
  try {
    const { productId } = req.body;
    let wl = await Wishlist.findOne({ customer: req.user.id });
    if (!wl) wl = new Wishlist({ customer: req.user.id, products: [], businesses: [] });
    const idx = wl.products.findIndex((p) => String(p) === productId);
    if (idx >= 0) wl.products.splice(idx, 1); else wl.products.push(productId);
    await wl.save();
    ok(res, { inWishlist: idx < 0 });
  } catch (e) { next(e); }
};

exports.toggleBusiness = async (req, res, next) => {
  try {
    const { businessId } = req.body;
    let wl = await Wishlist.findOne({ customer: req.user.id });
    if (!wl) wl = new Wishlist({ customer: req.user.id, products: [], businesses: [] });
    const idx = wl.businesses.findIndex((b) => String(b) === businessId);
    if (idx >= 0) wl.businesses.splice(idx, 1); else wl.businesses.push(businessId);
    await wl.save();
    ok(res, { following: idx < 0 });
  } catch (e) { next(e); }
};
