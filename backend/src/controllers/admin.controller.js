const adminService = require('../services/admin.service');
const { ok } = require('../utils/apiResponse');

exports.listVerifications = async (req, res, next) => {
  try {
    const { items, meta } = await adminService.listVerificationRequests(req.query);
    ok(res, items, meta);
  } catch (e) { next(e); }
};

exports.reviewBusiness = async (req, res, next) => {
  try { ok(res, await adminService.reviewBusiness(req.user.id, req.params.businessId, req.body)); }
  catch (e) { next(e); }
};
