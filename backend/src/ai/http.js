const logger = require('../utils/logger');
const errors = require('./errors');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const RETRYABLE = new Set([408, 429, 500, 502, 503, 504]);

// Test seam: tests set backoff to 0 so retries run instantly.
const settings = { baseBackoffMs: 400, maxBackoffMs: 4000 };

/**
 * POST JSON with a per-attempt timeout and a bounded number of retries (transient failures only:
 * network errors, timeouts, 408/429/5xx). 4xx other than those fail immediately.
 * Never logs request bodies or headers (they hold the API key and user content).
 */
async function postJson(url, { headers, body, timeoutMs = 20000, retries = 2, label = 'ai' }) {
  let lastKind = 'upstream';
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    let retryAfterMs = 0;
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...headers },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (res.ok) {
        try { return await res.json(); } catch { throw errors.badOutput(); }
      }
      logger.warn(`${label}: provider HTTP ${res.status} (attempt ${attempt + 1}/${retries + 1})`);
      if (!RETRYABLE.has(res.status)) throw errors.upstream();
      lastKind = res.status === 429 ? 'busy' : 'upstream';
      const ra = Number(res.headers?.get?.('retry-after'));
      if (Number.isFinite(ra) && ra > 0) retryAfterMs = Math.min(ra * 1000, settings.maxBackoffMs);
    } catch (e) {
      if (e?.isOperational) throw e; // already one of ours (bad output / non-retryable upstream)
      const timedOut = e?.name === 'TimeoutError' || e?.name === 'AbortError';
      logger.warn(`${label}: ${timedOut ? 'timeout' : 'network error'} (attempt ${attempt + 1}/${retries + 1})`);
      lastKind = timedOut ? 'timeout' : 'upstream';
    }
    if (attempt < retries) {
      const backoff = Math.min(settings.baseBackoffMs * 2 ** attempt, settings.maxBackoffMs);
      await sleep(Math.max(retryAfterMs, backoff * (0.5 + Math.random() / 2)) * (settings.baseBackoffMs === 0 ? 0 : 1));
    }
  }
  throw lastKind === 'timeout' ? errors.timeout() : lastKind === 'busy' ? errors.busy() : errors.upstream();
}

module.exports = { postJson, settings };
