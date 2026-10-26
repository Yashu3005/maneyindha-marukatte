# Testing Strategy

## Backend (Jest + Supertest)
- Unit: services (order state machine, pricing, auth token logic)
- API: supertest against app.js with mongodb-memory-server
- Included now: `tests/order.transition.test.js` (state machine rules)

## Frontend (Flutter)
- Unit: providers, repositories (mocked Dio)
- Widget: key screens' loading/empty/error/success states
- Integration: auth flow, checkout flow (Phase 16)

## CI
`.github/workflows/ci.yml` runs lint + tests for both stacks on every PR.
Rule from the spec: never claim tests pass unless they run green.
