const { Resend } = require('resend');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');

// Resend is the default email provider; Brevo is available with EMAIL_PROVIDER=brevo.
// API keys are read from the server environment only and are never logged or returned.
let client = null;

const provider = () => (process.env.EMAIL_PROVIDER || 'resend').toLowerCase();

// "Name <a@b.c>" or "a@b.c" -> { name, email }
function parseFrom(raw) {
  const m = /^\s*(?:"?([^"<]*?)"?\s*)?<([^>]+)>\s*$|^\s*([^\s<>]+)\s*$/.exec(String(raw || ''));
  if (!m) return null;
  return { name: (m[1] || '').trim() || undefined, email: (m[2] || m[3]).trim() };
}
exports.parseFrom = parseFrom;

function getClient() {
  if (!process.env.RESEND_API_KEY || !process.env.RESEND_FROM_EMAIL) {
    throw new AppError('Email service is not configured', 503, 'EMAIL_NOT_CONFIGURED');
  }
  if (!client) client = new Resend(process.env.RESEND_API_KEY);
  return client;
}

// Test seam — lets tests inject a stand-in client without touching the network.
exports._setClient = (c) => { client = c; };

// The logo in emails is the SAME file the website uses (frontend/web/brand/logo-email.png, served at
// <site>/brand/logo-email.png). Email clients need an absolute https URL and block inline/base64 images, so it
// is referenced by URL. Set APP_URL to the public website address (or EMAIL_LOGO_URL to a full image URL).
function logoUrl(env = process.env) {
  const safe = (u) => /^https:\/\/[^\s"'<>]+$/.test(u); // goes into an HTML attribute: no quotes, spaces or brackets
  if (env.EMAIL_LOGO_URL && safe(env.EMAIL_LOGO_URL)) return env.EMAIL_LOGO_URL;
  const publicOrigin = (o) => safe(o) && !/localhost|127\.0\.0\.1/.test(o);
  const base = (env.APP_URL && publicOrigin(env.APP_URL.trim()) ? env.APP_URL.trim()
    : String(env.CORS_ORIGINS || '').split(',').map((o) => o.trim()).find(publicOrigin));
  return base ? `${base.replace(/\/+$/, '')}/brand/logo-email.png` : null;
}
exports.logoUrl = logoUrl;
exports._otpHtml = (code, minutes) => otpHtml(code, minutes);

function otpHtml(code, minutes) {
  const logo = logoUrl();
  const header = logo
    ? `<tr><td align="center" style="padding-bottom:6px"><img src="${logo}" width="112" height="112" alt="Maneyindha Marukatte" style="display:block;border:0;outline:none;width:112px;height:112px"></td></tr>`
    : '';
  // Table layout + inline styles for broad email-client support; max-width keeps it mobile friendly.
  return `<!doctype html>
<html><body style="margin:0;padding:0;background:#f4f1ea;font-family:Arial,Helvetica,sans-serif;color:#2f3a1f">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f1ea;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;padding:28px">
${header}<tr><td align="center" style="font-size:20px;font-weight:bold;color:#4a5a2a;padding-bottom:12px">Maneyindha Marukatte</td></tr>
<tr><td style="font-size:16px;padding-bottom:16px">Use this code to sign in:</td></tr>
<tr><td align="center" style="padding:12px 0 20px"><span style="display:inline-block;font-size:34px;letter-spacing:10px;font-weight:bold;background:#eef0e4;border-radius:12px;padding:14px 22px">${code}</span></td></tr>
<tr><td style="font-size:14px;line-height:1.5;color:#555">This code expires in ${minutes} minutes and can be used once.<br>Never share it with anyone &mdash; Maneyindha Marukatte will never ask for it.<br>If you didn&rsquo;t request it, you can safely ignore this email.</td></tr>
</table></td></tr></table></body></html>`;
}

/**
 * Sends the sign-in code. Resolves with Resend's message id once Resend ACCEPTS the
 * request (that is not proof of inbox delivery — see scripts/check-resend-delivery.js).
 */
const subjectLine = 'Your Maneyindha Marukatte sign-in code';
const textBody = (code, minutes) => `Your Maneyindha Marukatte sign-in code is ${code}. It expires in ${minutes} minutes. Never share it with anyone. If you didn't request it, ignore this email.`;

// Brevo transactional email over REST (no SDK). Brevo only sends from a sender you have verified in its dashboard.
async function sendViaBrevo({ to, code, expiresMinutes }) {
  const apiKey = process.env.BREVO_API_KEY;
  const sender = parseFrom(process.env.BREVO_FROM_EMAIL);
  if (!apiKey || !sender) throw new AppError('Email service is not configured', 503, 'EMAIL_NOT_CONFIGURED');
  let res;
  try {
    res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': apiKey, accept: 'application/json', 'content-type': 'application/json' },
      body: JSON.stringify({
        sender, to: [{ email: to }], subject: subjectLine,
        htmlContent: otpHtml(code, expiresMinutes), textContent: textBody(code, expiresMinutes),
      }),
      signal: AbortSignal.timeout(15000),
    });
  } catch (e) {
    logger.error(`Brevo request failed: ${e?.name === 'TimeoutError' ? 'timeout' : 'network error'}`);
    throw new AppError('Could not send the email right now. Please try again.', 502, 'EMAIL_SEND_FAILED');
  }
  let body = null;
  try { body = await res.json(); } catch { /* non-JSON body */ }
  if (!res.ok || !body?.messageId) {
    // Provider error code only (e.g. unauthorized, invalid_parameter) — never the key or the body.
    logger.error(`Brevo rejected the email: HTTP ${res.status} ${body?.code || ''}`.trim());
    throw new AppError(res.status === 429 ? 'Email service is busy. Please try again in a moment.' : 'Could not send the email right now. Please try again.',
      res.status === 429 ? 503 : 502, 'EMAIL_SEND_FAILED');
  }
  logger.info(`OTP email accepted by Brevo (id=${body.messageId}); delivery is confirmed separately`);
  return { id: body.messageId };
}

exports.sendOtpEmail = async (args) => {
  if (provider() === 'brevo') return sendViaBrevo(args);
  const { to, code, expiresMinutes } = args;
  const resend = getClient();
  let result;
  try {
    result = await resend.emails.send({
      from: process.env.RESEND_FROM_EMAIL,
      to: [to],
      subject: subjectLine,
      html: otpHtml(code, expiresMinutes),
      text: textBody(code, expiresMinutes),
    });
  } catch (e) {
    // The SDK reports API errors in `result.error`; a throw means a network-level failure.
    logger.error(`Resend request failed: ${e.name || 'Error'}`);
    throw new AppError('Could not send the email right now. Please try again.', 502, 'EMAIL_SEND_FAILED');
  }
  const { data, error } = result || {};
  if (error || !data?.id) {
    // Log the provider's error NAME only (e.g. invalid_api_key, validation_error) — never the key.
    logger.error(`Resend rejected the email: ${error?.name || 'unknown'}`);
    const rateLimited = error?.name === 'rate_limit_exceeded' || error?.statusCode === 429;
    throw new AppError(
      rateLimited ? 'Email service is busy. Please try again in a moment.' : 'Could not send the email right now. Please try again.',
      rateLimited ? 503 : 502,
      'EMAIL_SEND_FAILED'
    );
  }
  // The message id is not sensitive and is what you look up with scripts/check-resend-delivery.js.
  logger.info(`OTP email accepted by Resend (id=${data.id}); delivery is confirmed separately`);
  return { id: data.id };
};

// A short notice (for example "your account was suspended"). Best effort: the action it reports has already
// happened, so a delivery problem is logged and reported as { sent: false }, never thrown.
const escHtml = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function noticeHtml({ heading, message }) {
  const logo = logoUrl();
  const header = logo
    ? `<tr><td align="center" style="padding-bottom:6px"><img src="${logo}" width="96" height="96" alt="Maneyindha Marukatte" style="display:block;border:0;width:96px;height:96px"></td></tr>`
    : '';
  return `<!doctype html>
<html><body style="margin:0;padding:0;background:#f4f1ea;font-family:Arial,Helvetica,sans-serif;color:#2f3a1f">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f1ea;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;padding:28px">
${header}<tr><td align="center" style="font-size:20px;font-weight:bold;color:#4a5a2a;padding-bottom:12px">${escHtml(heading)}</td></tr>
<tr><td style="font-size:16px;line-height:1.5;padding-bottom:12px">${escHtml(message).replace(/\n/g, '<br>')}</td></tr>
<tr><td style="font-size:13px;line-height:1.5;color:#777">Maneyindha Marukatte</td></tr>
</table></td></tr></table></body></html>`;
}
exports._noticeHtml = noticeHtml;

exports.sendNoticeEmail = async ({ to, subject, heading, message }) => {
  if (!to) return { sent: false };
  const html = noticeHtml({ heading, message });
  const text = `${heading}\n\n${message}\n\nManeyindha Marukatte`;
  try {
    if (provider() === 'brevo') {
      const apiKey = process.env.BREVO_API_KEY;
      const sender = parseFrom(process.env.BREVO_FROM_EMAIL);
      if (!apiKey || !sender) return { sent: false };
      const res = await fetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: { 'api-key': apiKey, accept: 'application/json', 'content-type': 'application/json' },
        body: JSON.stringify({ sender, to: [{ email: to }], subject, htmlContent: html, textContent: text }),
        signal: AbortSignal.timeout(15000),
      });
      if (!res.ok) { logger.warn(`Notice email rejected by Brevo: HTTP ${res.status}`); return { sent: false }; }
      return { sent: true };
    }
    if (!process.env.RESEND_API_KEY || !process.env.RESEND_FROM_EMAIL) return { sent: false };
    const { data, error } = (await getClient().emails.send({ from: process.env.RESEND_FROM_EMAIL, to: [to], subject, html, text })) || {};
    if (error || !data?.id) { logger.warn(`Notice email rejected by Resend: ${error?.name || 'unknown'}`); return { sent: false }; }
    return { sent: true };
  } catch (e) {
    logger.warn(`Notice email failed: ${e?.name || 'Error'}`);
    return { sent: false };
  }
};

/** Looks up what Resend recorded for a message (delivered / bounced / …). */
exports.getDeliveryStatus = async (id) => {
  if (provider() === 'brevo') throw new AppError('Delivery lookup is only available with Resend; check the Brevo dashboard (Transactional → Logs)', 400, 'EMAIL_STATUS_UNSUPPORTED');
  const { data, error } = await getClient().emails.get(id);
  if (error) throw new AppError('Could not fetch delivery status', 502, 'EMAIL_STATUS_FAILED');
  return { id: data.id, lastEvent: data.last_event, to: data.to, createdAt: data.created_at };
};
