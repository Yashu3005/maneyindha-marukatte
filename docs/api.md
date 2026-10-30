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
| Businesses | `GET /businesses` (filters: `category`, `q`, `minRating`, `openNow`, `hasVideo`, `sort=rating|newest|name`), `/businesses/nearby` (`lat`,`lng`,`radiusKm`, same filters), `/businesses/mine`, `/businesses/:id`; `POST /businesses`; `PATCH /businesses/:id/location`; `POST /businesses/:id/documents` (private upload), `GET /businesses/:id/documents`, `DELETE /businesses/:id/documents/:docId`, `POST /businesses/:id/verification-documents` (submit) |
| Products | `GET /products`, `/products/:id`; `POST /products`; `DELETE /products/:id` |
| Cart / wishlist / reviews | `/cart`, `/cart/items`, `/cart/coupon`, `/wishlist/*`, `/reviews/*` |
| Orders | `POST /orders` (`paymentMethod: cod|razorpay`), `GET /orders/mine` (orders I placed), `GET /orders/received` (shop owners: orders for my shops), `PATCH /orders/:id/status` |
| Payments | `POST /payments/razorpay/order`, `/payments/razorpay/verify`, `/payments/razorpay/webhook`; `GET /payments/status/:orderId` |
| AI | `POST /ai/product-description` (entrepreneurs), `POST /ai/assistant` (customer help; real AI only, 503 `AI_NOT_CONFIGURED` if no key) |
| Rewards | `GET /rewards/me` (badge, progress, reward coupons with status) |
| Ratings | `POST /reviews` (needs a delivered order: `orderId` + `productId`), `GET /reviews/to-rate`, `GET /reviews/business/:id`, `GET /businesses/:id/rating-summary` |
| Shop video | `POST /businesses/:id/promo-video/signature`, `POST /businesses/:id/promo-video`, `DELETE /businesses/:id/promo-video` (owner of an approved shop) |
| App | `GET /app/download`, `GET /app/download-qr.png` |
| Media | `GET /images` |
| Admin (the one configured admin only) | `POST /auth/admin/login`; `GET /admin/stats`, `GET /admin/users`, `PATCH /admin/users/:id/status`, `GET /admin/verifications`, `POST /admin/verifications/:businessId` (approve only from `in_review` with documents on file), `GET /admin/verifications/:businessId/documents/:docId/link`, `DELETE /admin/businesses/:businessId/promo-video` |
| System | `GET /health` (outside `/api/v1`) |

## Rate limits
Global 500 / 15 min / IP. Auth routes 60 / 15 min / IP. `POST /auth/otp/send`: 10 / hour / IP plus a 60 s per-email cooldown. AI: 30 / hour / user. Avatar upload: 20 / hour. Payments (create/verify): 60 / 15 min. Counters are in process memory.

## Standards
- Joi validation on writes (422), ownership checks on entrepreneur writes, server-side pricing
- Versioning: breaking changes go to `/api/v2`

- Entrepreneur badges: `GET /rewards/seller` (entrepreneur only).
