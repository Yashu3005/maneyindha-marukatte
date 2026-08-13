// Consistent response envelope for every endpoint.
exports.ok = (res, data, meta = undefined, status = 200) =>
  res.status(status).json({ success: true, data, meta });

exports.fail = (res, message, status = 400, code = undefined) =>
  res.status(status).json({ success: false, error: { message, code } });
