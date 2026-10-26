# AI service layer

`backend/src/ai/` — feature code calls `ai/index.js`; providers are adapters behind `completeJson()`.

```
ai/index.js              generateProductDescription(), status()
ai/http.js               POST with per-attempt timeout + bounded retries (network, 408, 429, 5xx; never other 4xx)
ai/errors.js             client-safe error mapping
ai/providers/gemini.js   Google Gemini REST (generateContent), key sent in x-goog-api-key header
ai/providers/openai.js   OpenAI REST (chat completions, json_schema response format)
```

Select with `AI_PROVIDER=gemini|openai` (default `gemini`). Model names are configuration (`GEMINI_MODEL`, `OPENAI_MODEL`) because providers retire models; set one that your account can use. Docs: [Gemini API](https://ai.google.dev/gemini-api/docs), [OpenAI API](https://platform.openai.com/docs).

## Endpoint
`POST /api/v1/ai/product-description` — entrepreneurs only, 30 requests/hour/user (in-memory per instance; use a shared store behind several instances).
Body `{name, category?, details?, language?}` → `{description, provider}`.

## Behaviour
- Only the product text is sent to the provider — never user identity, contact or order data.
- Product text is passed as delimited **data**, with a system instruction to ignore instructions inside it. This reduces, not eliminates, prompt-injection risk; the output is also validated.
- The answer must parse as JSON, match `{description: string 20–600 chars}`, and have `finishReason = STOP`; HTML/control characters are stripped. Anything else → `502 AI_BAD_OUTPUT`.
- Timeout (`AI_TIMEOUT_MS`, default 20 s) per attempt, 2 retries with exponential backoff and jitter (honours `Retry-After`, capped). Errors: `503 AI_NOT_CONFIGURED`, `503 AI_RATE_LIMITED`, `504 AI_TIMEOUT`, `502 AI_PROVIDER_ERROR`. Provider messages and keys are never returned.
- **No fake output:** when AI is unconfigured or failing, the endpoint fails; nothing is fabricated. The app shows the error and the seller types the description by hand. The result is a *draft* the seller reviews.

## Status
Unit/HTTP tests use a stubbed `fetch` (request shape, validation, retries, timeouts, errors). **No live provider call has been made from this repository's test environment.** Run one real request yourself after setting a key (see `IMPLEMENTATION_REPORT.md`).

## Not built
Recommendations, forecasting, review sentiment, translation — listed in the roadmap only.
