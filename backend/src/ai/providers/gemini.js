const { postJson } = require('../http');
const errors = require('../errors');

// Google Gemini via the REST generateContent endpoint (no SDK dependency).
// Model is configurable because Google retires/renames models; set GEMINI_MODEL to a currently
// available text model. The API key is sent in a header, never in the URL, so it cannot leak into logs.
const DEFAULT_MODEL = 'gemini-2.5-flash';
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
  // Blocked prompts / safety stops / truncation must not be treated as an answer.
  if (!cand || data?.promptFeedback?.blockReason || (cand.finishReason && cand.finishReason !== 'STOP')) throw errors.badOutput();
  const text = (cand.content?.parts || []).map((p) => p.text || '').join('');
  try { return JSON.parse(text); } catch { throw errors.badOutput(); }
};
