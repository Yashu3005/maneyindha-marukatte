const authService = require('../services/auth.service');
const { ok } = require('../utils/apiResponse');

exports.register = async (req, res, next) => {
  try { ok(res, await authService.register(req.body), undefined, 201); } catch (e) { next(e); }
};
exports.login = async (req, res, next) => {
  try { ok(res, await authService.login(req.body)); } catch (e) { next(e); }
};
exports.refresh = async (req, res, next) => {
  try { ok(res, await authService.refresh(req.body.refreshToken)); } catch (e) { next(e); }
};
exports.firebaseExchange = async (req, res, next) => {
  try { ok(res, await authService.exchangeFirebaseToken(req.body)); } catch (e) { next(e); }
};
exports.sendOtp = async (req, res, next) => {
  try { ok(res, await authService.sendOtp(req.body.email)); } catch (e) { next(e); }
};
exports.verifyOtp = async (req, res, next) => {
  try { ok(res, await authService.verifyOtp(req.body)); } catch (e) { next(e); }
};
