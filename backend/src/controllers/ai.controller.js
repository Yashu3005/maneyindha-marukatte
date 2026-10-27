const ai = require('../ai');
const { ok } = require('../utils/apiResponse');

exports.productDescription = async (req, res, next) => {
  try { ok(res, await ai.generateProductDescription(req.body)); }
  catch (e) { next(e); }
};

exports.assistant = async (req, res, next) => {
  try { ok(res, await require('../services/assistant.service').reply(req.user.id, req.body)); }
  catch (e) { next(e); }
};
