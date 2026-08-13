# API Architecture

Base: `/api/v1` — JWT bearer auth — consistent envelope:

```json
{ "success": true,  "data": ..., "meta": { "page": 1, "limit": 20, "total": 123 } }
{ "success": false, "error": { "message": "...", "code": "..." } }
```

## Implemented (Phase 1 skeleton)

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | /auth/register | – | email or phone + password |
| POST | /auth/login | – | returns access + refresh tokens |
| POST | /auth/refresh | – | rotate tokens |
| GET | /businesses/nearby?lat=&lng=&radiusKm= | – | geo query, approved businesses only |
| GET | /businesses/:id | – | |
| POST | /businesses | entrepreneur | |
| GET | /products?q=&category=&page=&limit=&sort= | – | text search + pagination |
| GET | /products/:id | – | |
| POST | /products | entrepreneur | ownership enforced |
| POST | /orders | customer | server-side pricing, stock check |
| GET | /orders/mine | any | role-scoped |
| PATCH | /orders/:id/status | any* | state-machine validated (*role guards per transition in Phase 3) |

## Standards

- Joi validation on every write endpoint (422 on failure)
- Rate limiting: global 500/15min; tighten auth endpoints in Phase 17
- Swagger/OpenAPI: mount `swagger-ui-express` at `/api/docs` in Phase 3
- Versioning: breaking changes → `/api/v2`

## Phase 2 additions
| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | /auth/firebase-exchange | – | Firebase ID token → backend JWT pair; role settable only at first login, admin roles blocked |
| GET | /api/docs | – | Swagger UI (interactive API docs) |

Auth endpoints now rate-limited to 30 req/15min.
New models: Review, Cart, Coupon, Wishlist, Wallet, Transaction, Notification.

## Phase 3 additions
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET/DELETE | /cart | customer | totals computed server-side, stale coupons auto-ignored |
| POST/PATCH | /cart/items | customer | one business per cart; qty 0 removes |
| POST | /cart/coupon | customer | full validation: window, business scope, min amount, per-user + total usage limits |
| POST | /reviews | customer | orderId ⇒ verified purchase (delivered orders only); duplicate → 409 |
| GET | /reviews/product/:productId | – | paginated |
| POST | /reviews/:id/reply | entrepreneur | own business only |
| GET/POST | /wishlist, /wishlist/products, /wishlist/businesses | customer | toggle semantics |
| POST | /businesses/:id/verification-documents | entrepreneur | status → in_review |
| GET | /admin/verifications | admin | filter by status |
| POST | /admin/verifications/:businessId | admin | approve / reject / request_info + owner notification |

Order checkout now: re-validates coupon, computes discount, atomically decrements stock, increments coupon usage, clears cart.
Ratings on products and businesses recomputed on every new review.
