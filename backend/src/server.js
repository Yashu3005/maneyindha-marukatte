const { loadEnv, assertEnv, emailConfigIssues } = require('./config/env');
loadEnv();
const http = require('http');
const app = require('./app');
const { connectMongo } = require('./config/db');
const { initSocket } = require('./sockets');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 5000;

(async () => {
  assertEnv();
  if (process.env.NODE_ENV === 'production' && !process.env.CORS_ORIGINS) {
    logger.warn('CORS_ORIGINS is not set — the API accepts requests from any origin');
  }
  if (process.env.NODE_ENV !== 'production') {
    // Not fatal in development, but say so loudly: OTP emails cannot be sent without it.
    emailConfigIssues().forEach((m) => logger.warn(`Email OTP will not work: ${m}`));
  }
  await connectMongo();
  const server = http.createServer(app);
  initSocket(server);
  server.listen(PORT, () => logger.info(`API listening on :${PORT}`));
})().catch((err) => {
  logger.error('Fatal startup error', err);
  process.exit(1);
});
