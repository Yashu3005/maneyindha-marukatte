/* Asks Resend what actually happened to a message (accepted != delivered).
   Usage: node scripts/check-resend-delivery.js <message-id>
   last_event is e.g. sent | delivered | delivery_delayed | bounced | complained. */
require('../src/config/env').loadEnv();
const emailService = require('../src/services/email.service');

const id = process.argv[2];
if (!id) { console.error('Usage: node scripts/check-resend-delivery.js <message-id>'); process.exit(1); }
emailService.getDeliveryStatus(id)
  .then((s) => console.log(JSON.stringify(s, null, 2)))
  .catch((e) => { console.error(`Failed: ${e.message}`); process.exit(1); });
