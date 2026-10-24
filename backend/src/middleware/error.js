const logger = require('../utils/logger');

exports.notFound = (_req, res) =>
  res.status(404).json({ success: false, error: { message: 'Route not found' } });

exports.errorHandler = (err, _req, res, _next) => {
  const status = err.statusCode || 500;
  if (status >= 500) logger.error(err.stack || err.message);
  // Never leak stack traces to clients.
  res.status(status).json({
    success: false,
    error: {
      message: err.isOperational ? err.message : 'Internal server error',
      code: err.code,
    },
  });
};
