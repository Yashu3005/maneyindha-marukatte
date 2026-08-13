// Vercel serverless entry — cached DB connection, resilient errors.
require('dotenv').config();
const mongoose = require('mongoose');
const app = require('../src/app');

let ready = null;
function ensureDb() {
  if (!ready) {
    mongoose.set('strictQuery', true);
    ready = mongoose
      .connect(process.env.MONGODB_URI, { serverSelectionTimeoutMS: 8000 })
      .catch((e) => {
        ready = null; // allow retry on next request
        throw e;
      });
  }
  return ready;
}

module.exports = async (req, res) => {
  try {
    if (!req.url.startsWith('/health')) await ensureDb();
    return app(req, res);
  } catch (e) {
    console.error('DB/init error:', e.message);
    res.statusCode = 500;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({
      success: false,
      error: { message: 'Database connection failed: ' + e.message },
    }));
  }
};
