const { postJson } = require('../http');
const errors = require('../errors');

// OpenAI via the REST Chat Completions endpoint with a JSON-schema response format (no SDK dependency).
const DEFAULT_MODEL = 'gpt-4o-mini';

exports.name = 'openai';
exports.isConfigured = () => !!process.env.OPENAI_API_KEY;

exports.completeJson = async ({ system, prompt, jsonSchema, maxTokens = 1500 }) => {
  if (!process.env.OPENAI_API_KEY) throw errors.notConfigured('OPENAI_API_KEY');
  const data = await postJson('https://api.openai.com/v1/chat/completions', {
    headers: { Authorization: `Bearer ${process.env.OPENAI_API_KEY}` },
    body: {
      model: process.env.OPENAI_MODEL || DEFAULT_MODEL,
      messages: [{ role: 'system', content: system }, { role: 'user', content: prompt }],
      max_tokens: maxTokens,
      temperature: 0.7,
      response_format: { type: 'json_schema', json_schema: { name: 'result', strict: true, schema: jsonSchema } },
    },
    timeoutMs: Number(process.env.AI_TIMEOUT_MS) || 20000,
    label: 'openai',
  });
  const choice = data?.choices?.[0];
  if (!choice || choice.finish_reason !== 'stop' || choice.message?.refusal) throw errors.badOutput();
  try { return JSON.parse(choice.message?.content ?? ''); } catch { throw errors.badOutput(); }
};
