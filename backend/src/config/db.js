const mongoose = require('mongoose');
const logger = require('../utils/logger');

async function connectMongo() {
  mongoose.set('strictQuery', true);
  await mongoose.connect(process.env.MONGODB_URI);
  logger.info('MongoDB connected');
}

module.exports = { connectMongo };
