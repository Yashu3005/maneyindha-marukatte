const orderService = require('../services/order.service');
const { ok } = require('../utils/apiResponse');

exports.create = async (req, res, next) => {
  try { ok(res, await orderService.createOrder(req.user.id, req.body), undefined, 201); }
  catch (e) { next(e); }
};

exports.myOrders = async (req, res, next) => {
  try { res.set('Cache-Control', 'no-store'); ok(res, await orderService.ordersForUser(req.user)); }
  catch (e) { next(e); }
};

exports.received = async (req, res, next) => {
  try { res.set('Cache-Control', 'no-store'); ok(res, await orderService.receivedOrders(req.user)); }
  catch (e) { next(e); }
};

exports.updateStatus = async (req, res, next) => {
  try { ok(res, await orderService.transition(req.params.id, req.body.status, req.user)); }
  catch (e) { next(e); }
};
