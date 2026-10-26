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

// Resend only sends from a domain you have verified, never from a consumer mailbox.
const FREE_MAIL = ['gmail.com', 'googlemail.com', 'yahoo.com', 'outlook.com', 'hotmail.com', 'icloud.com', 'proton.me', 'protonmail.com'];

// Returns human-readable problems with the Resend configuration (never the values).
function emailConfigIssues(env = process.env) {
  const issues = [];
  const providerName = (env.EMAIL_PROVIDER || 'resend').toLowerCase();
  if (providerName === 'brevo') {
    if (!env.BREVO_API_KEY) issues.push('BREVO_API_KEY is not set');
    if (!env.BREVO_FROM_EMAIL) issues.push('BREVO_FROM_EMAIL is not set');
    else if (!/<[^<>\s@]+@[^<>\s@]+\.[^<>\s@]+>|^[^<>\s@]+@[^<>\s@]+\.[^<>\s@]+$/.test(env.BREVO_FROM_EMAIL.trim())) {
      issues.push('BREVO_FROM_EMAIL is not a valid address (use "Name <you@example.com>", a sender verified in Brevo)');
    }
    return issues;
  }
  if (providerName !== 'resend') return [`EMAIL_PROVIDER "${providerName}" is not supported (use resend or brevo)`];
  if (!env.RESEND_API_KEY) issues.push('RESEND_API_KEY is not set');
  else if (!/^re_[A-Za-z0-9_]{10,}$/.test(env.RESEND_API_KEY)) issues.push('RESEND_API_KEY does not look like a Resend key (expected re_…)');
  if (!env.RESEND_FROM_EMAIL) issues.push('RESEND_FROM_EMAIL is not set');
  else {
    const m = /<([^>]+)>|^([^\s<>]+)$/.exec(env.RESEND_FROM_EMAIL.trim());
    const addr = (m && (m[1] || m[2]) || '').toLowerCase();
    const domain = addr.split('@')[1];
    if (!domain) issues.push('RESEND_FROM_EMAIL is not a valid address (use "Name <user@your-domain>")');
    else if (FREE_MAIL.includes(domain)) {
      issues.push(`RESEND_FROM_EMAIL uses ${domain}, which Resend cannot send from — verify your own domain at resend.com/domains (or use onboarding@resend.dev for testing only)`);
    }
  }
  return issues;
}

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
    // Email OTP is the primary sign-in path, so production must be able to send it.
    const emailIssues = emailConfigIssues(env);
    if (emailIssues.length) throw new Error(`Email (Resend) configuration problem: ${emailIssues.join('; ')}`);
  }
}

module.exports = { loadEnv, assertEnv, emailConfigIssues, REQUIRED };
