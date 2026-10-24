const adminService = require('../services/admin.service');
const { ok } = require('../utils/apiResponse');

exports.getStats = async (req, res, next) => {
  try {
    const stats = await adminService.getStats();
    ok(res, stats);
  } catch (e) {
    next(e);
  }
};

exports.listVerifications = async (req, res, next) => {
  try {
    const { items, meta } = await adminService.listVerificationRequests(req.query);
    ok(res, items, meta);
  } catch (e) {
    next(e);
  }
};

exports.reviewBusiness = async (req, res, next) => {
  try {
    ok(res, await adminService.reviewBusiness(req.user.id, req.params.businessId, req.body));
  } catch (e) {
    next(e);
  }
};

exports.listEntrepreneurs = async (req, res, next) => {
  try {
    const { items, meta } = await adminService.listEntrepreneurs(req.query);
    ok(res, items, meta);
  } catch (e) {
    next(e);
  }
};

exports.assignBadge = async (req, res, next) => {
  try {
    ok(res, await adminService.assignBadge(req.user.id, req.params.businessId, req.body.badge));
  } catch (e) {
    next(e);
  }
};

exports.listProducts = async (req, res, next) => {
  try {
    const { items, meta } = await adminService.listProducts(req.query);
    ok(res, items, meta);
  } catch (e) {
    next(e);
  }
};

exports.moderateProduct = async (req, res, next) => {
  try {
    ok(res, await adminService.moderateProduct(req.user.id, req.params.productId, req.body));
  } catch (e) {
    next(e);
  }
};

exports.listCategories = async (req, res, next) => {
  try {
    ok(res, await adminService.listCategories());
  } catch (e) {
    next(e);
  }
};

exports.createCategory = async (req, res, next) => {
  try {
    ok(res, await adminService.createCategory(req.user.id, req.body), undefined, 201);
  } catch (e) {
    next(e);
  }
};

exports.updateCategory = async (req, res, next) => {
  try {
    ok(res, await adminService.updateCategory(req.user.id, req.params.id, req.body));
  } catch (e) {
    next(e);
  }
};

exports.getTrendAnalysis = async (req, res, next) => {
  try {
    ok(res, await adminService.getTrendAnalysis(req.query));
  } catch (e) {
    next(e);
  }
};

exports.getActivityLogs = async (req, res, next) => {
  try {
    ok(res, await adminService.getActivityLogs());
  } catch (e) {
    next(e);
  }
};
