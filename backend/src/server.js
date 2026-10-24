require('dotenv').config();
const http = require('http');
const app = require('./app');
const { connectMongo } = require('./config/db');
const { initSocket } = require('./sockets');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 5000;

(async () => {
  await connectMongo();
  const server = http.createServer(app);
  initSocket(server);
  server.listen(PORT, () => logger.info(`API listening on :${PORT}`));
})().catch((err) => {
  logger.error('Fatal startup error', err);
  process.exit(1);
});
