# Testing

## Backend (Jest + Supertest)
```bash
cd backend && npm ci && npm test && npm run lint
```
Tests run against the real Express app. MongoDB and the third-party providers are replaced at the edge:
- Mongoose model statics are stubbed (`jest.spyOn`) or replaced by a small in-memory model (`tests/fakes/memoryModel.js`)
- Resend, Razorpay, Cloudinary and Gemini/OpenAI are stand-ins; HTTP providers are stubbed at `fetch`
- Signatures in payment tests are computed independently with Node `crypto`, and QR tests decode the real PNG with `jsQR`
- `tests/openapi.test.js` fails if a served route is missing from `openapi.json` (or the reverse)

Suites: auth/OTP (service + full HTTP journey), payments, order/payment gating, avatar upload, AI layer, QR, location, OpenAPI drift, plus the earlier controller/middleware/socket suites.

### What these tests do NOT prove
Nothing here contacts MongoDB, Resend, Razorpay, Cloudinary, Gemini/OpenAI or a real browser. See `IMPLEMENTATION_REPORT.md` for the checks you must run once with real (test-mode) credentials.

## Frontend (Flutter)
```bash
cd frontend && flutter pub get && flutter analyze && flutter test
```
The Flutter changes for OTP resend, checkout/Razorpay, avatars, QR, "Write with AI" and "Near me" were written without a Flutter SDK available and have **not** been compiled or run. New dependencies: `image_picker`, `geolocator`.

## CI
`.github/workflows/ci.yml` runs lint + tests for both stacks. Never report tests as passing unless they ran green.
