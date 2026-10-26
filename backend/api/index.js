// Vercel serverless entry — wraps the Express app with a cached DB connection.
// NOTE: Socket.IO and the in-memory OTP store need a persistent server; see docs/deployment.md.
const { loadEnv, assertEnv } = require('../src/config/env');
loadEnv();
const mongoose = require('mongoose');
const app = require('../src/app');

let ready = null;
function ensureDb() {
  if (!ready) {
    assertEnv();
    mongoose.set('strictQuery', true);
    ready = mongoose.connect(process.env.MONGODB_URI).catch((err) => {
      ready = null; // don't cache a failed connect for the life of the instance
      throw err;
    });
  }
  return ready;
}

module.exports = async (req, res) => {
  try {
    await ensureDb();
  } catch (err) {
    console.error('DB connection failed:', err.message);
    return res.status(503).json({ success: false, error: { message: 'Service temporarily unavailable' } });
  }
  return app(req, res);
};
