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

exports.documentLink = async (req, res, next) => {
  try {
    const docs = require('../services/verificationDoc.service');
    res.set('Cache-Control', 'no-store');
    ok(res, await docs.adminDocumentLink(req.params.businessId, req.params.docId));
  } catch (e) { next(e); }
};

exports.stats = async (_req, res, next) => {
  try { res.set('Cache-Control', 'no-store'); ok(res, await adminService.getStats()); } catch (e) { next(e); }
};

exports.listUsers = async (req, res, next) => {
  try {
    const { items, meta } = await adminService.listUsers(req.query);
    ok(res, items, meta);
  } catch (e) { next(e); }
};

exports.setUserStatus = async (req, res, next) => {
  try { ok(res, await adminService.setUserActive(req.params.id, req.body.isActive, { reason: req.body.reason })); } catch (e) { next(e); }
};

exports.setBusinessStatus = async (req, res, next) => {
  try { ok(res, await adminService.setBusinessActive(req.params.businessId, req.body.isActive, { reason: req.body.reason })); } catch (e) { next(e); }
};

exports.listPromoVideos = async (req, res, next) => {
  try { ok(res, await require('../services/promoVideo.service').listForReview(req.query.status || 'pending')); } catch (e) { next(e); }
};
exports.reviewPromoVideo = async (req, res, next) => {
  try { ok(res, await require('../services/promoVideo.service').reviewVideo(req.params.businessId, req.body.action, req.body.reason)); } catch (e) { next(e); }
};

exports.removePromoVideo = async (req, res, next) => {
  try { ok(res, await require('../services/promoVideo.service').adminRemoveVideo(req.params.businessId)); } catch (e) { next(e); }
};

// ---- read-only insight views (owners, shops, products, badges, growth) ----
const insights = require('../services/adminInsights.service');
const noStore = (res) => res.set('Cache-Control', 'no-store');
exports.owners = async (req, res, next) => { try { noStore(res); const { items, meta } = await insights.owners(req.query); ok(res, items, meta); } catch (e) { next(e); } };
exports.ownerDetail = async (req, res, next) => { try { noStore(res); ok(res, await insights.ownerDetail(req.params.id)); } catch (e) { next(e); } };
exports.shops = async (req, res, next) => { try { noStore(res); const { items, meta } = await insights.shops(req.query); ok(res, items, meta); } catch (e) { next(e); } };
exports.products = async (req, res, next) => { try { noStore(res); const { items, meta } = await insights.products(req.query); ok(res, items, meta); } catch (e) { next(e); } };
exports.badges = async (req, res, next) => { try { noStore(res); ok(res, await insights.badges()); } catch (e) { next(e); } };
exports.growth = async (req, res, next) => { try { noStore(res); ok(res, await insights.growth(req.query)); } catch (e) { next(e); } };
