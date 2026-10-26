const crypto = require('crypto');

// ASCII slug; for names with no ASCII letters (e.g. Kannada) falls back to a short
// stable hash so distinct names never collapse into the same "-" slug.
exports.slugify = (name) => {
  const base = String(name || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return base || `x${crypto.createHash('sha1').update(String(name || '')).digest('hex').slice(0, 8)}`;
};
