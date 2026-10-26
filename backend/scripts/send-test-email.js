/* Sends ONE real test email through the configured provider (Resend by default, Brevo with EMAIL_PROVIDER=brevo) using your server env, to prove the key + sender work.
   Usage:  node scripts/send-test-email.js [recipient]
   Default recipient is Resend's test inbox (delivered@resend.dev). While you only have the
   shared onboarding@resend.dev sender, Resend delivers to your own account email only.
   Prints the Resend message id — never the API key. Then run check-resend-delivery.js <id>. */
require('../src/config/env').loadEnv();
const { emailConfigIssues } = require('../src/config/env');
const emailService = require('../src/services/email.service');

(async () => {
  const issues = emailConfigIssues();
  if (issues.length) {
    console.error('Email is not configured correctly:\n - ' + issues.join('\n - '));
    process.exit(1);
  }
  const to = process.argv[2] || 'delivered@resend.dev';
  const { id } = await emailService.sendOtpEmail({ to, code: '000000', expiresMinutes: 5 });
  const brevo = (process.env.EMAIL_PROVIDER || '').toLowerCase() === 'brevo';
  console.log(`Accepted by ${brevo ? 'Brevo' : 'Resend'}. message id: ${id}\n` + (brevo ? 'Check delivery in the Brevo dashboard: Transactional -> Logs.' : `Next: node scripts/check-resend-delivery.js ${id}`));
})().catch((e) => { console.error(`Failed: ${e.message} (${e.code || 'no code'})`); process.exit(1); });
