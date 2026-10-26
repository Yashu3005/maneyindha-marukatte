# Maneyindha Marukatte — End-to-End Audit Report

Date: 2026-10-26 · Scope: whole repository (`backend/`, `frontend/`, CI, Docker, Vercel config, docs)

## 0. Read this first — what could and could not be verified

| Area | Result |
|---|---|
| Backend lint (`npm run lint`) | **PASS** (before and after) |
| Backend unit/HTTP tests | **PASS** — 7 existing → **174** now (9 suites), run on a clean `npm ci` |
| Live HTTP tests against the real Express app (auth, RBAC, validation, error handling) | **PASS** (86 tests, supertest) |
| Anything that needs a **real MongoDB** (actual reads/writes, `$near`, `$text`, unique indexes, seed script, end-to-end flows) | **BLOCKED** — no `mongod` in the sandbox; the MongoDB download host (`fastdl.mongodb.org`) is blocked by the sandbox network policy, and Go/GitHub routes to a Mongo-compatible server were also unavailable. I did not work around the block or fake a database. |
| Flutter `analyze` / `test` / build / UI run / responsive checks | **BLOCKED** — no Flutter SDK, download host blocked. Frontend was reviewed statically only. |
| Razorpay, Firebase, Cloudinary, Google Maps, Gemini/OpenAI, Redis, Pexels (live) | **BLOCKED / NOT IMPLEMENTED** — no credentials; several are not wired into the code at all (see §6). |
| Deployment | **NOT DONE** by design (no deploys, no production env changes). |

How I tested the DB-dependent logic without a DB: service/controller tests stub only the **Mongoose model static methods** (`jest.spyOn(Order, 'findById')`, …); the business logic under test is real. These prove the logic, **not** that the queries behave identically on MongoDB. **First thing to do on your machine:** run the app against a real Mongo (`docker compose up -d mongo redis`, `npm run seed`) and smoke-test the flows in §3.

To show the new tests aren't vacuous, I ran them against the **original** source: 71 of 160 failed there (negative-quantity orders accepted, mass assignment, document leak, order IDOR, demo OTP, malformed-JSON message, …) and all pass on the fixed code.

---

## 1. Architecture & stack

- **Frontend:** Flutter (Dart ≥3.4), Riverpod, go_router, Dio, shared_preferences. Web-first MVP; ~3.6k lines, ~25 routes.
- **Backend:** Node ≥20, Express 4 (`routes → controllers → services → models`), Joi validation, JWT (15 min access / 30 d refresh), bcryptjs, Socket.IO, Winston, Swagger UI.
- **DB:** MongoDB via Mongoose 8 (13 models). Redis client exists but is **unused**.
- **Auth:** password login, email-OTP login (demo), Firebase→JWT exchange (needs creds).
- **Deploy targets:** Vercel serverless (`backend/api/index.js`), Docker (`Dockerfile`, `docker-compose.yml`), GitHub Actions CI.
- **Data flow:** Flutter → `Dio` (Bearer JWT) → `/api/v1/*` → Mongoose → MongoDB. Socket.IO is initialised but nothing emits and the frontend never connects.

## 2. Features / pages inspected (static review of every file)

Landing, email→OTP→profile→role onboarding, login/register, customer shell (home, search, profile), business page, product page, cart, checkout (COD only), orders, seller onboarding (business → documents → review → submitted → status → credentials → security questions), seller shell (products, orders, earnings, profile), admin verification screen.

## 3. API inventory & results

"HTTP layer" = routing, auth (401), RBAC (403), validation (422), error shape — **tested live with supertest**. "DB logic" = behaviour that needs MongoDB — tested with stubbed models where noted, otherwise **BLOCKED**.

| Endpoint | HTTP layer | DB logic |
|---|---|---|
| GET `/health`, GET `/api/docs` | PASS | n/a (health does not check DB — see §11) |
| POST `/auth/register` | PASS | PASS (stub: dup check, hashing) / BLOCKED real DB |
| POST `/auth/login` | PASS | PASS (stub: wrong pw, disabled, enumeration-safe msg) / BLOCKED real DB |
| POST `/auth/refresh` | PASS | BLOCKED (user lookup) |
| POST `/auth/firebase-exchange` | PASS (422) | BLOCKED — no Firebase credentials |
| POST `/auth/otp/send` | PASS | PASS (in-memory) |
| POST `/auth/otp/verify` | PASS | PASS (stub); **real OTP delivery NOT IMPLEMENTED** (§6) |
| GET/PATCH `/users/me` | PASS (401) | NOT TESTED beyond auth |
| POST `/users/me/role`, `/credentials`, `/security-questions` | PASS | PASS (stub) |
| GET `/businesses`, `/businesses/nearby` | PASS (422 on bad coords) | PASS (stub: documents stripped, clamps) / **`$near` BLOCKED** |
| GET `/businesses/:id` | PASS | PASS (stub: visibility rules) |
| GET `/businesses/mine` | PASS | NOT TESTED |
| POST `/businesses` | PASS | PASS (stub: whitelist) |
| POST `/businesses/:id/verification-documents` | PASS | NOT TESTED (DB) |
| GET `/products` | PASS | PASS (stub: visibility, clamps) / **`$text` BLOCKED** |
| GET `/products/:id`, POST `/products`, DELETE `/products/:id` | PASS | PASS (stub) |
| GET/POST/PATCH/DELETE `/cart…`, POST `/cart/coupon` | PASS | PASS (stub: stock, approval) / coupon path partly NOT TESTED |
| POST `/orders` | PASS | PASS (stub: pricing, merge, rollback, coupon) |
| GET `/orders/mine` | PASS (401) | NOT TESTED |
| PATCH `/orders/:id/status` | PASS | PASS (stub: authorization matrix, CAS, restock) |
| GET `/reviews/product/:id`, `/business/:id`, POST `/reviews`, POST `/reviews/:id/reply` | PASS (401/403/422) | NOT TESTED (DB) |
| GET `/wishlist`, POST `/wishlist/products`, `/businesses` | PASS | NOT TESTED (DB) |
| GET/POST `/admin/verifications…` | PASS | NOT TESTED (DB) |
| GET `/images` | PASS | PASS (placeholder path, Pexels failure path with stubbed `fetch`); live Pexels BLOCKED |
| Socket.IO `join` | n/a | PASS (authorization function, stubbed) / live socket NOT TESTED |

## 4. Frontend audit (static only — Flutter SDK unavailable)

- All API calls match real backend routes/methods; payload shapes are compatible with the new validation (checked each call site against the Joi schemas).
- **FAIL (fixed, unverified):** refresh token was discarded, so every session died after 15 minutes. See B-12.
- **NOT TESTED:** rendering, console errors, loading/empty/error states at runtime, responsive layouts, `flutter analyze/test`.
- Existing `widget_test.dart` was not run.
- Default API base URL is `http://localhost:5050/api/v1` while the backend/README default is port 5000 (README now explains; no code change).
- "Upload File" on seller onboarding is a **stock-photo picker** (Pexels/picsum via `/images`), not a file upload — see §6.

## 5. Backend / database audit

- Layering is clean; response envelope is consistent; Joi `stripUnknown` is applied where validation existed.
- Many write endpoints had **no validation** and spread `req.body` straight into models (B-02, B-09).
- Schema/indexes read as sane (2dsphere, text, unique slugs/codes). Not exercised on a real DB.
- No multi-document transactions (fine on standalone Mongo); order creation now uses reserve-then-compensate (B-04).
- Seed script reads correctly but **could not be run** (no DB).

## 6. External integrations

| Integration | Status |
|---|---|
| Razorpay (docs say payments) | **NOT IMPLEMENTED** — no payment/webhook code; orders are COD, `payment.*` is never set. Nothing to verify; webhook signature checks N/A until built. |
| Firebase Auth exchange | Code present; **BLOCKED** (no credentials). `firebase-admin` has known advisories needing a major upgrade (§9). |
| Email/SMS for OTP | **NOT IMPLEMENTED** — OTPs are generated but never delivered. Email-OTP onboarding cannot work in production until a provider is chosen. The OTP store is in-memory (not safe for multiple instances/serverless). |
| Cloudinary / Firebase Storage | **NOT IMPLEMENTED** — no upload endpoint. ID-proof "uploads" are stock photos, so the verification workflow cannot collect real documents yet. |
| Google Maps | **NOT IMPLEMENTED** (default Bengaluru coordinates used). |
| Gemini / OpenAI | Placeholder adapters that throw; nothing calls them. |
| Redis | Client file exists, never imported. |
| Pexels | Code path verified with stubbed `fetch` (success, 429, throw). Live call BLOCKED (no key). |

## 7. Authentication & security findings

Fixed: B-01 … B-11 below. Still open: §10.
Verified by tests: tokens signed with a wrong secret, expired tokens, `alg:none`, a refresh token used as an access token, and an access token used as a refresh token are all rejected; NoSQL operator injection on login → 422; privileged roles cannot be self-registered.

## 8. Bugs discovered, root causes, fixes

| ID | Sev | Finding & root cause | Fix |
|---|---|---|---|
| B-01 | **Critical** | `PATCH /orders/:id/status` only checked "logged in". Any user could set any order to any legal next status (mark own order delivered/refunded, confirm/reject others'). | Participant check (customer / shop owner / assigned partner / admin; strangers get 404), per-role allowed targets, customer may only cancel pending/confirmed, refunds admin-only, compare-and-set update (409 on race). |
| B-02 | **Critical** | `POST /businesses` did `Business.create({...req.body})` → client could send `verification.status:"approved"` and skip admin review (also owner/rating/isActive). | Field whitelist + Joi schema; `verification` always defaults to pending. |
| B-03 | **Critical** | `GET /businesses`, `/nearby`, `/:id` returned the full document incl. `verification.documents` (ID-proof URLs, reviewer, rejection reason) to anonymous users; unapproved shops reachable by id. | Documents/reviewer fields excluded from all public responses; unapproved shops visible only to owner/admin (new `optionalAuth`). |
| B-04 | **Critical** | `POST /orders` had no validation: negative quantity ⇒ negative subtotal and **stock increase**; fractional/NaN qty; duplicate lines bypassed stock check; bad/missing `businessId` ⇒ stock decremented then `Order.create` failed (stock leak); coupon `usedCount` incremented before stock check (coupon burned on failure); orders accepted for unapproved shops. | Joi schema (qty 1–50 integers, ids, address required unless pickup); approved/open shop required; duplicate lines merged; atomic reserve of stock then coupon (with total-limit guard) then create, with compensation on any failure. |
| B-05 | **Critical** | Hard-coded demo OTP `029403` (in the public repo) accepted whenever `NODE_ENV !== 'production'` — the Dockerfile didn't set it and Railway/Render don't by default ⇒ anyone could log in as **any email, including seeded `admin@mm.dev`**. | Demo OTP now requires `ALLOW_DEMO_OTP=true` **and** non-production; Dockerfile sets `NODE_ENV=production`; OTP can never log into admin/super_admin; 5-attempt lockout per code. |
| B-06 | High | `POST /products` mass assignment (rating, isActive, …), no validation (negative price/stock). | Whitelist + Joi. |
| B-07 | High | Unapproved shops' catalogue public via `/products?business=` and `/products/:id`; `limit`/`sort` unbounded/arbitrary. | Visible only to owner/admin until approved; limit capped (50), sort whitelisted. Cart/checkout refuse unapproved shops. |
| B-08 | High | Socket.IO: no auth, `cors:*`, any client could `join` any `order:<id>` room. | JWT handshake auth, CORS from `CORS_ORIGINS`, per-room authorization (own `user:` room, own orders), `chat:*` refused. (No emitter exists yet.) |
| B-09 | High | `POST /users/me/role` let admins / delivery partners silently demote themselves to customer/entrepreneur. | Only customer↔entrepreneur may toggle. |
| B-10 | High | No `trust proxy`: behind Vercel/Railway/Render the rate limiter keyed on the proxy IP (all users throttled together; express-rate-limit warns). | `TRUST_PROXY` env, default 1 in production. |
| B-11 | High | Dependencies: 20 advisories (1 critical `proxy-addr`; high in `express`, `body-parser`, `joi`, `engine.io`). | `npm audit fix` within semver ranges → 9 remain (see §9). |
| B-12 | High | Flutter stored only the access token; refresh token ignored ⇒ users hit 401 every 15 min. | Store refresh token; on 401 call `/auth/refresh` once and retry. **Unverified (no Flutter SDK).** |
| B-13 | High | README says `cp .env.example .env` at repo root, but the API only read `backend/.env` ⇒ quick-start boots with undefined secrets (every login 500s, every token 401s). | `config/env.js` loads `backend/.env` then repo-root `.env`; fail-fast validation of `MONGODB_URI/JWT_*`; production rejects placeholder/short/identical secrets. |
| B-14 | Medium | Malformed JSON → 400 with message "Internal server error"; invalid ObjectId → 500; duplicate key → 500. | Error handler maps these to 400/422/409/413. |
| B-15 | Medium | Register didn't lowercase email: duplicate-account check bypass (`A@x.com` vs `a@x.com`) and login with mixed case failed. | Joi `.lowercase()` on email/username. |
| B-16 | Medium | Deactivated users could still log in with password. | `isActive` checked at login. |
| B-17 | Medium | `/images`: any Pexels outage/timeout ⇒ 500 (comment promised placeholders); `count<=0` unchecked. | Inner try/catch + 5 s timeout; count clamped 1–12. |
| B-18 | Medium | Security-question answers stored in plaintext (code comment admitted it). | bcrypt-hashed, case-insensitive. Nothing reads them yet. |
| B-19 | Medium | `api/index.js` cached a *failed* Mongo connection forever (until cold start); no env validation. | Cache cleared on failure; 503 JSON response. |
| B-20 | Medium | Category from name: non-Latin names all slugified to `"-"` and the upsert **renamed** the shared category. | Hash-based fallback slug; `$setOnInsert`. |
| B-21 | Medium | Cart stock checked only against the increment; `PATCH` quantity unchecked. | Checked against resulting quantity / current stock. |
| B-22 | Low | Dockerfile ran as root; `nearby`/lists accepted NaN/negative paging; admin list `limit` unbounded; ESLint lacked jest globals. | `USER node`; shared `parsePage`; Joi on admin query; globals added. |

## 9. Files modified

**Backend source:** `app.js` (trust proxy, CORS parsing) · `server.js`, `api/index.js`, `scripts/seed.js` (env loading/validation) · **new** `config/env.js`, `utils/pagination.js`, `utils/slug.js`, `validators/order.validator.js` · `middleware/auth.js` (`optionalAuth`), `middleware/error.js` · `services/order.service.js` (rewritten), `auth.service.js`, `cart.service.js` · `controllers/business.controller.js`, `product.controller.js`, `users.controller.js` · `routes/business|product|order|admin|images.routes.js` · `sockets/index.js` · `validators/auth.validator.js`.
**Backend infra:** `Dockerfile`, `eslint.config.js`, `package-lock.json` (audit fixes; `package.json` unchanged — no new dependencies).
**Tests (new):** `helpers.js`, `http.api.test.js`, `order.service.test.js`, `auth.otp.test.js`, `controllers.test.js`, `middleware.test.js`, `sockets.test.js`.
**Frontend:** `services/api_client.dart`, `services/auth_state.dart` (refresh token).
**Docs/config:** `.env.example` (CORS_ORIGINS, TRUST_PROXY, ALLOW_DEMO_OTP), `README.md`, this report.

## 10. Remaining issues & decisions needed (not changed)

1. **Behaviour change to be aware of:** the OTP demo flow now needs `ALLOW_DEMO_OTP=true` in your `.env` (already in `.env.example`). Without it the app shows no demo code and OTP login fails.
2. **OTP delivery provider** (email/SMS) and a shared store (Redis) — required before any real launch.
3. **Real document upload** (Cloudinary/Firebase Storage) — verification currently accepts any URL and the UI supplies stock photos. Documents are also not access-controlled beyond owner/admin visibility.
4. **Payments** (Razorpay + webhook signature verification) are not built.
5. **Delivery partner flow:** no endpoint assigns `deliveryPartner`; `assigned` status is unreachable. `refunded` moves no money. Product variants are ignored in cart/order pricing.
6. Models without routes: Notification (written on verification, never readable), Wallet, Transaction, Coupon admin/CRUD, wishlist/follow counters.
7. `firebase-admin` chain (`firebase-admin` + `node-forge` high; 7 moderate via google-cloud libs): needs a **major** upgrade (`npm audit fix --force` → firebase-admin 14); not done without your OK.
8. `requireAuth` trusts JWT claims for ≤15 min (role changes/deactivation lag); login has no per-account lockout (IP rate limit only); password policy differs (register ≥8, set-credentials ≥6); login timing reveals whether an account exists.
9. Vercel serverless cannot host Socket.IO or the in-memory OTP store (docs already recommend Railway/Render for the API).
10. `/health` doesn't check the DB; CORS defaults to `*` when `CORS_ORIGINS` is unset (a warning is logged in production); `openapi.json` documents only 27 of 39 operations and is out of date; `docker-compose.yml` `version:` is obsolete (warning only); frontend/backend default ports differ (5050 vs 5000).
11. CI runs backend lint+tests and `flutter analyze/test` (the latter never run here). Consider adding `mongodb-memory-server` API tests to CI — the dependency is already present — and running them locally first, since I could not.

## 11. Production readiness: **NOT READY**

The critical authorization, privacy and input-validation holes are closed and covered by tests, but the product cannot go live until OTP delivery, real document upload and (if online payments are intended) Razorpay exist; the DB-backed flows must be smoke-tested on a real MongoDB; and the Flutter changes must be compiled and run (`flutter analyze && flutter test`).

## 12. Suggested verification on your machine (≈15 min)

```bash
docker compose up -d mongo redis
cp .env.example .env            # set JWT_SECRET / JWT_REFRESH_SECRET; MONGODB_URI=mongodb://localhost:27017/maneyindha
cd backend && npm ci && npm run seed && npm run dev
# then, with the seeded users (password123): log in as customer@mm.dev,
# add a product to the cart, place an order, then as asha@mm.dev confirm it;
# confirm the customer CANNOT confirm/deliver; cancel and check stock is restored;
# GET /api/v1/businesses and check no verification.documents appear.
cd ../frontend && flutter pub get && flutter analyze && flutter test
```
