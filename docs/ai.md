# AI Service Layer

Location: `backend/src/ai/` — provider-agnostic by design.

```
ai/index.js            → public functions the app calls
ai/providers/gemini.js → adapter (Phase 13)
ai/providers/openai.js → adapter (Phase 13)
```

Switch with `AI_PROVIDER=gemini|openai`. Feature code never imports a provider directly.

## Planned functions per audience

- Customer: recommendations (collaborative + content-based hybrid), semantic search re-ranking, chatbot
- Entrepreneur: demand forecasting (seasonal + festival features), price suggestions, auto product descriptions
- Trust: review sentiment, fake-review heuristics + LLM scoring, anomaly flags for reward fraud
- Language: translation for the 7 supported locales

Start with description generation + recommendations (highest value/effort ratio); forecasting needs order history to exist first.
