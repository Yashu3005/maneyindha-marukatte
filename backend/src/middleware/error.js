const logger = require('../utils/logger');

exports.notFound = (_req, res) =>
  res.status(404).json({ success: false, error: { message: 'Route not found' } });

// Maps well-known library errors to correct 4xx responses instead of a blanket 500.
function classify(err) {
  if (err.isOperational) return { status: err.statusCode || 400, message: err.message, code: err.code, retryAfterSeconds: err.retryAfterSeconds };
  if (err.type === 'entity.parse.failed') return { status: 400, message: 'Malformed JSON body' };
  if (err.type === 'entity.too.large') return { status: 413, message: 'Request body too large' };
  if (err.name === 'CastError') return { status: 400, message: `Invalid ${err.path || 'identifier'}` };
  if (err.name === 'ValidationError' && err.errors) {
    return { status: 422, message: Object.values(err.errors).map((e) => e.message).join('; ') };
  }
  if (err.code === 11000) return { status: 409, message: 'Duplicate value' };
  return null;
}

exports.errorHandler = (err, _req, res, _next) => {
  const known = classify(err);
  if (!known) logger.error(err.stack || err.message);
  const status = known ? known.status : 500;
  if (known?.retryAfterSeconds) res.set('Retry-After', String(known.retryAfterSeconds));
  // Never leak stack traces or internals to clients.
  res.status(status).json({
    success: false,
    error: {
      message: known ? known.message : 'Internal server error',
      code: known ? known.code : undefined,
      ...(known?.retryAfterSeconds ? { retryAfterSeconds: known.retryAfterSeconds } : {}),
    },
  });
};
