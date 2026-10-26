// Safe page/limit parsing — query values arrive as arbitrary strings.
exports.parsePage = (query = {}, { defLimit = 20, maxLimit = 50 } = {}) => {
  const page = Math.max(1, parseInt(query.page, 10) || 1);
  const limit = Math.min(maxLimit, Math.max(1, parseInt(query.limit, 10) || defLimit));
  return { page, limit, skip: (page - 1) * limit };
};

exports.isObjectId = (v) => typeof v === 'string' && /^[0-9a-fA-F]{24}$/.test(v);
