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

function otpHtml(code, minutes) {
  // Table layout + inline styles for broad email-client support; max-width keeps it mobile friendly.
  return `<!doctype html>
<html><body style="margin:0;padding:0;background:#f4f1ea;font-family:Arial,Helvetica,sans-serif;color:#2f3a1f">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f1ea;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;padding:28px">
<tr><td style="font-size:20px;font-weight:bold;color:#4a5a2a;padding-bottom:8px">Maneyindha Marukatte</td></tr>
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

/** Looks up what Resend recorded for a message (delivered / bounced / …). */
exports.getDeliveryStatus = async (id) => {
  if (provider() === 'brevo') throw new AppError('Delivery lookup is only available with Resend; check the Brevo dashboard (Transactional → Logs)', 400, 'EMAIL_STATUS_UNSUPPORTED');
  const { data, error } = await getClient().emails.get(id);
  if (error) throw new AppError('Could not fetch delivery status', 502, 'EMAIL_STATUS_FAILED');
  return { id: data.id, lastEvent: data.last_event, to: data.to, createdAt: data.created_at };
};
