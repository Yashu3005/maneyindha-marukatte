const Razorpay = require('razorpay');
const AppError = require('../utils/AppError');

let client = null;

// Secrets stay on the server. Missing configuration is reported as a clear 503, never with values.
exports.getRazorpay = () => {
  if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
    throw new AppError('Online payments are not configured', 503, 'PAYMENTS_NOT_CONFIGURED');
  }
  if (!client) client = new Razorpay({ key_id: process.env.RAZORPAY_KEY_ID, key_secret: process.env.RAZORPAY_KEY_SECRET });
  return client;
};

// Test seam — inject a stand-in SDK client.
exports._setRazorpay = (c) => { client = c; };
