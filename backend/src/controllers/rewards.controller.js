const rewardsService = require('../services/rewards.service');
const { ok } = require('../utils/apiResponse');

exports.seller = async (req, res, next) => {
  try { res.set('Cache-Control', 'no-store'); ok(res, await rewardsService.getSellerBadges(req.user.id)); } catch (e) { next(e); }
};

exports.mine = async (req, res, next) => {
  try { res.set('Cache-Control', 'no-store'); ok(res, await rewardsService.getRewards(req.user.id)); } catch (e) { next(e); }
};
