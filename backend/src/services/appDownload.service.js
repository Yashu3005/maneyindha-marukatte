const net = require('net');
const { URL } = require('url');
const QRCode = require('qrcode');

// The QR always encodes a destination the operator configured — nothing is invented. Candidates are read
// in this order: APP_DOWNLOAD_URL (explicit override), then APP_ANDROID_URL, APP_IOS_URL, APP_WEB_URL.
const SOURCES = ['APP_DOWNLOAD_URL', 'APP_ANDROID_URL', 'APP_IOS_URL', 'APP_WEB_URL'];

const PRIVATE_V4 = [/^10\./, /^127\./, /^169\.254\./, /^192\.168\./, /^172\.(1[6-9]|2\d|3[01])\./, /^0\./];
function isPrivateHost(host) {
  const h = host.replace(/^\[|\]$/g, '').toLowerCase();
  if (h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal')) return true;
  const kind = net.isIP(h);
  if (kind === 4) return PRIVATE_V4.some((re) => re.test(h));
  if (kind === 6) return h === '::1' || h === '::' || /^f[cd]/.test(h) || h.startsWith('fe80');
  return !h.includes('.'); // bare hostnames ("intranet") are never public
}

/** Returns { ok:true, url } or { ok:false, reason }. Only public https destinations are accepted. */
function validateDestination(raw) {
  let u;
  try { u = new URL(String(raw).trim()); } catch { return { ok: false, reason: 'not a valid URL' }; }
  if (u.protocol !== 'https:') return { ok: false, reason: 'must use https' };
  if (u.username || u.password) return { ok: false, reason: 'must not contain credentials' };
  if (isPrivateHost(u.hostname)) return { ok: false, reason: 'must be a public hostname (not localhost or a private address)' };
  if (u.href.length > 500) return { ok: false, reason: 'too long' };
  return { ok: true, url: u.href };
}

// Describe the destination by what it is, never as "live on a store" — we do not check that the listing exists.
function describe(url) {
  const host = new URL(url).hostname.toLowerCase();
  if (host === 'play.google.com') return { platform: 'android', label: 'Google Play listing (as configured)' };
  if (host === 'apps.apple.com' || host === 'testflight.apple.com') return { platform: 'ios', label: host === 'testflight.apple.com' ? 'Apple TestFlight link (as configured)' : 'App Store listing (as configured)' };
  return { platform: 'web', label: 'Web app link (open in a browser; installable from the browser menu where supported)' };
}

/** Current configuration state, safe to show to anyone. */
function getDownloadInfo(env = process.env) {
  for (const key of SOURCES) {
    if (!env[key]) continue;
    const v = validateDestination(env[key]);
    if (!v.ok) return { configured: false, problem: `${key} ${v.reason}` };
    return { configured: true, url: v.url, source: key, ...describe(v.url) };
  }
  return { configured: false, problem: 'No download destination has been configured' };
}

async function renderQrPng(url) {
  return QRCode.toBuffer(url, { type: 'png', errorCorrectionLevel: 'M', margin: 4, width: 512 });
}

module.exports = { getDownloadInfo, validateDestination, renderQrPng, SOURCES };
