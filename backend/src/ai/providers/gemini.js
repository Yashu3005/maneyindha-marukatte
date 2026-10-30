const { postJson } = require('../http');
const errors = require('../errors');
const logger = require('../../utils/logger');

// Google Gemini via the REST generateContent endpoint (no SDK dependency).
// Model is configurable because Google retires/renames models; set GEMINI_MODEL to a currently
// available text model. The API key is sent in a header, never in the URL, so it cannot leak into logs.
const DEFAULT_MODEL = 'gemini-3.5-flash-lite';
const BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

exports.name = 'gemini';
exports.isConfigured = () => !!process.env.GEMINI_API_KEY;

/** Returns the model's JSON answer as a parsed object (schema is a Gemini-style OpenAPI subset). */
exports.completeJson = async ({ system, prompt, schema, maxTokens = 1500 }) => {
  if (!process.env.GEMINI_API_KEY) throw errors.notConfigured('GEMINI_API_KEY');
  const model = process.env.GEMINI_MODEL || DEFAULT_MODEL;
  const data = await postJson(`${BASE}/${encodeURIComponent(model)}:generateContent`, {
    headers: { 'x-goog-api-key': process.env.GEMINI_API_KEY },
    body: {
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.7, maxOutputTokens: maxTokens,
        responseMimeType: 'application/json', responseSchema: schema,
      },
    },
    timeoutMs: Number(process.env.AI_TIMEOUT_MS) || 20000,
    label: 'gemini',
  });
  const cand = data?.candidates?.[0];
  const block = data?.promptFeedback?.blockReason;
  if (!cand || block) {
    logger.warn(`Gemini gave no answer: blockReason=${block || 'none'}`);
    throw errors.badOutput(block ? 'BLOCKED' : 'NO_ANSWER');
  }
  // Skip the model's private "thought" parts; only the final answer is JSON.
  const text = (cand.content?.parts || []).filter((p) => !p.thought).map((p) => p.text || '').join('').trim();
  const stoppedEarly = cand.finishReason && cand.finishReason !== 'STOP'; // cut off, or stopped by a safety filter
  const parsed = stoppedEarly ? undefined : extractJson(text);
  if (parsed !== undefined) return parsed;
  // Only the reason is logged (never the prompt or the answer text).
  logger.warn(`Gemini answer rejected: finishReason=${cand.finishReason || 'none'} length=${text.length}`);
  throw errors.badOutput(stoppedEarly ? cand.finishReason : (text ? 'NOT_JSON' : 'EMPTY'));
};

/** Parses the model's JSON, tolerating a ```json fence or a sentence around it. Returns undefined if there is none. */
function extractJson(text) {
  if (!text) return undefined;
  const attempts = [text, text.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/, '')];
  const a = text.indexOf('{'); const b = text.lastIndexOf('}');
  if (a !== -1 && b > a) attempts.push(text.slice(a, b + 1));
  for (const t of attempts) {
    try { const v = JSON.parse(t); if (v && typeof v === 'object') return v; } catch { /* try the next form */ }
  }
  return undefined;
}
