# API

Base: `/api/v1` · JWT bearer auth · interactive docs at `/api/docs` · machine-readable spec: [`backend/src/docs/openapi.json`](../backend/src/docs/openapi.json).
The spec is checked against the running Express routes by `backend/tests/openapi.test.js`, so a route cannot exist undocumented (or the reverse) while tests are green.

Envelope:
```json
{ "success": true,  "data": ..., "meta": { "page": 1, "limit": 20, "total": 123 } }
{ "success": false, "error": { "message": "...", "code": "...", "retryAfterSeconds": 42 } }
```
Status codes used: 400 bad input/credentials · 401 not signed in · 403 wrong role · 404 not found *or not yours* · 409 conflict · 413/415 upload too large / wrong type · 422 validation · 429 rate limited (see `Retry-After`) · 502/503/504 upstream provider problems.

## Endpoint groups (see the spec for bodies and responses)

| Group | Endpoints |
|---|---|
| Auth | `POST /auth/otp/send`, `/auth/otp/verify`, `/auth/refresh`, `/auth/logout`, `/auth/logout-all`, `/auth/register`, `/auth/login`, `/auth/firebase-exchange` |
| Users | `GET/PATCH /users/me`, `POST/DELETE /users/me/avatar`, `POST /users/me/role`, `/users/me/credentials`, `/users/me/security-questions` |
| Businesses | `GET /businesses`, `/businesses/nearby`, `/businesses/mine`, `/businesses/:id`; `POST /businesses`; `PATCH /businesses/:id/location`; `POST /businesses/:id/verification-documents` |
| Products | `GET /products`, `/products/:id`; `POST /products`; `DELETE /products/:id` |
| Cart / wishlist / reviews | `/cart`, `/cart/items`, `/cart/coupon`, `/wishlist/*`, `/reviews/*` |
| Orders | `POST /orders` (`paymentMethod: cod|razorpay`), `GET /orders/mine`, `PATCH /orders/:id/status` |
| Payments | `POST /payments/razorpay/order`, `/payments/razorpay/verify`, `/payments/razorpay/webhook`; `GET /payments/status/:orderId` |
| AI | `POST /ai/product-description` |
| App | `GET /app/download`, `GET /app/download-qr.png` |
| Media | `GET /images` |
| Admin | `GET /admin/verifications`, `POST /admin/verifications/:businessId` |
| System | `GET /health` (outside `/api/v1`) |

## Rate limits
Global 500 / 15 min / IP. Auth routes 60 / 15 min / IP. `POST /auth/otp/send`: 10 / hour / IP plus a 60 s per-email cooldown. AI: 30 / hour / user. Avatar upload: 20 / hour. Payments (create/verify): 60 / 15 min. Counters are in process memory.

## Standards
- Joi validation on writes (422), ownership checks on entrepreneur writes, server-side pricing
- Versioning: breaking changes go to `/api/v2`
