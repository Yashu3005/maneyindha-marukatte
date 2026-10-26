// Provider-agnostic AI service layer.
// Switch providers via AI_PROVIDER env var without touching feature code.

const providers = {
  gemini: () => require('./providers/gemini'),
  openai: () => require('./providers/openai'),
};

function getProvider() {
  const name = process.env.AI_PROVIDER || 'gemini';
  const load = providers[name];
  if (!load) throw new Error(`Unknown AI provider: ${name}`);
  return load();
}

module.exports = {
  generateProductDescription: (input) => getProvider().complete(
    `Write a warm, concise product description (max 80 words) for: ${JSON.stringify(input)}`
  ),
  // Add: recommendations, demand forecasting, sentiment analysis, translation...
};
