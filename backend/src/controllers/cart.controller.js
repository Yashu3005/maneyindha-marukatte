const cartService = require('../services/cart.service');
const { ok } = require('../utils/apiResponse');

exports.get = async (req, res, next) => {
  try { ok(res, await cartService.getCart(req.user.id)); } catch (e) { next(e); }
};
exports.addItem = async (req, res, next) => {
  try { ok(res, await cartService.addItem(req.user.id, req.body), undefined, 201); } catch (e) { next(e); }
};
exports.updateItem = async (req, res, next) => {
  try { ok(res, await cartService.updateItem(req.user.id, req.body)); } catch (e) { next(e); }
};
exports.clear = async (req, res, next) => {
  try { ok(res, await cartService.clearCart(req.user.id)); } catch (e) { next(e); }
};
exports.applyCoupon = async (req, res, next) => {
  try { ok(res, await cartService.applyCoupon(req.user.id, req.body.code)); } catch (e) { next(e); }
};
