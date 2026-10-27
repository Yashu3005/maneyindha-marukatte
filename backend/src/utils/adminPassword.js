const crypto = require('crypto');

// The single administrator's password is never stored in the code or the database.
// The server holds only a salted scrypt hash in ADMIN_PASSWORD_HASH, created by
// `npm run admin:hash`. Format: scrypt:<N>:<salt b64url>:<hash b64url> (no "$", so it
// survives shells, .env files and hosting dashboards unchanged).
const N = 16384;
const KEY_LEN = 64;
const MIN_LENGTH = 12;

const scrypt = (password, salt, n = N) =>
  new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, KEY_LEN, { N: n, maxmem: 64 * 1024 * 1024 }, (err, key) => (err ? reject(err) : resolve(key)));
  });

exports.MIN_LENGTH = MIN_LENGTH;

exports.hashPassword = async (password) => {
  if (typeof password !== 'string' || password.length < MIN_LENGTH) {
    throw new Error(`Admin password must be at least ${MIN_LENGTH} characters`);
  }
  const salt = crypto.randomBytes(16);
  const key = await scrypt(password, salt);
  return `scrypt:${N}:${salt.toString('base64url')}:${key.toString('base64url')}`;
};

// Constant-time. Returns false (never throws) for a malformed stored value so a bad
// env var fails closed.
exports.verifyPassword = async (password, stored) => {
  try {
    if (typeof password !== 'string' || typeof stored !== 'string') return false;
    const [scheme, nStr, saltB64, hashB64] = stored.split(':');
    const n = Number(nStr);
    if (scheme !== 'scrypt' || !Number.isInteger(n) || n < 1024 || n > 1 << 20 || !saltB64 || !hashB64) return false;
    const expected = Buffer.from(hashB64, 'base64url');
    if (expected.length !== KEY_LEN) return false;
    const actual = await scrypt(password.slice(0, 256), Buffer.from(saltB64, 'base64url'), n);
    return crypto.timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
};

// Compares two strings without leaking where they differ.
exports.safeEqual = (a, b) => {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
};
