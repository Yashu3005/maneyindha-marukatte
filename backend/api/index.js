// Vercel serverless entry — wraps the Express app with a cached DB connection.
require('dotenv').config();
const mongoose = require('mongoose');
const app = require('../src/app');

let ready = null;
function ensureDb() {
  if (!ready) {
    mongoose.set('strictQuery', true);
    ready = mongoose.connect(process.env.MONGODB_URI);
  }
  return ready;
}

module.exports = async (req, res) => {
  await ensureDb();
  return app(req, res);
};
