const orderService = require('../services/order.service');
const { ok } = require('../utils/apiResponse');

exports.create = async (req, res, next) => {
  try {
    ok(res, await orderService.createOrder(req.user.id, req.body), undefined, 201);
  } catch (e) {
    next(e);
  }
};

exports.getById = async (req, res, next) => {
  try {
    ok(res, await orderService.getOrderById(req.params.id, req.user));
  } catch (e) {
    next(e);
  }
};

exports.myOrders = async (req, res, next) => {
  try {
    ok(res, await orderService.ordersForUser(req.user));
  } catch (e) {
    next(e);
  }
};

exports.updateStatus = async (req, res, next) => {
  try {
    ok(res, await orderService.transition(req.params.id, req.body.status, req.user));
  } catch (e) {
    next(e);
  }
};

exports.cancel = async (req, res, next) => {
  try {
    ok(res, await orderService.cancelOrder(req.params.id, req.user.id));
  } catch (e) {
    next(e);
  }
};

exports.requestAfterSales = async (req, res, next) => {
  try {
    ok(res, await orderService.requestAfterSales(req.params.id, req.user.id, req.body));
  } catch (e) {
    next(e);
  }
};

exports.decideAfterSales = async (req, res, next) => {
  try {
    ok(res, await orderService.decideAfterSales(req.params.id, req.user.id, req.body));
  } catch (e) {
    next(e);
  }
};

exports.startReturn = async (req, res, next) => {
  try {
    ok(res, await orderService.startReturn(req.params.id, req.user.id));
  } catch (e) {
    next(e);
  }
};

exports.confirmReturn = async (req, res, next) => {
  try {
    ok(res, await orderService.confirmReturn(req.params.id, req.user.id));
  } catch (e) {
    next(e);
  }
};

exports.afterSalesList = async (req, res, next) => {
  try {
    ok(res, await orderService.getAfterSalesForEntrepreneur(req.user));
  } catch (e) {
    next(e);
  }
};
