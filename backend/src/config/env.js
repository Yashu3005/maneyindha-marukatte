const path = require('path');
const dotenv = require('dotenv');

// The README tells developers to create `.env` at the REPO ROOT, but the API is
// started from `backend/`. Load backend/.env first, then the repo-root .env.
// dotenv never overrides variables that are already set, so real host env vars win.
function loadEnv() {
  dotenv.config();
  dotenv.config({ path: path.resolve(__dirname, '../../../.env') });
}

const REQUIRED = ['MONGODB_URI', 'JWT_SECRET', 'JWT_REFRESH_SECRET'];

// Fails fast with a clear message instead of surfacing later as opaque 401/500s
// (jsonwebtoken throws "secretOrPrivateKey must have a value" on every login).
function assertEnv(env = process.env) {
  const missing = REQUIRED.filter((k) => !env[k]);
  if (missing.length) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }
  if (env.NODE_ENV === 'production') {
    const weak = ['JWT_SECRET', 'JWT_REFRESH_SECRET'].filter(
      (k) => env[k].length < 32 || env[k].startsWith('replace-with')
    );
    if (weak.length) {
      throw new Error(`Weak or placeholder secrets in production: ${weak.join(', ')} (use 32+ random characters)`);
    }
    if (env.JWT_SECRET === env.JWT_REFRESH_SECRET) {
      throw new Error('JWT_SECRET and JWT_REFRESH_SECRET must differ');
    }
  }
}

module.exports = { loadEnv, assertEnv, REQUIRED };
