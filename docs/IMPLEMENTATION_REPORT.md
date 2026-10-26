# Implementation report — seven feature upgrade

Status vocabulary: **PASS** = executed here and green · **BLOCKED** = cannot be executed in this environment (no network to the provider / no SDK / no database) · **NOT TESTED** = written but never run. Nothing below is claimed as working unless it says PASS, and PASS always means *against stand-ins for the external service*, never the real one.

## 1. Existing architecture and stack
Flutter web-first app (Riverpod, go_router, Dio; only a `web/` platform folder exists) + Node/Express 4 REST API (Mongoose 8, Joi, JWT, Socket.IO, Winston) on MongoDB. Layers: routes → controllers → services → models. Earlier phase: full audit, 22 fixes (`AUDIT_REPORT.md`).

## 2. Features and files inspected
Auth/OTP, users, businesses, orders (state machine), cart, checkout, seller onboarding, customer/seller shells, images route, env loading, error handler, docs, OpenAPI, tests. Findings that shaped the work: the "profile photo" was a *required* stock-photo picker; seller "documents" are stock-photo URLs; every new shop got a hard-coded Bengaluru location; public endpoints returned exact coordinates; the AI adapters were stubs that throw; there is no delivery-partner assignment or tracking in the product; the app has no android/ios folders.

## 3. Features implemented and actual status

| # | Feature | Backend | Flutter | Live external check |
|---|---|---|---|---|
| 1 | Resend email OTP | **PASS** (stand-in Resend, in-memory DB) | **NOT TESTED** (uncompiled) | **BLOCKED** (no network to Resend; needs your verified domain) |
| 2 | Razorpay sandbox payments | **PASS** (stand-in SDK; independent HMAC) | **NOT TESTED** | **BLOCKED** (no network to Razorpay) |
| 3 | Documentation / OpenAPI | **PASS** (route-drift test) | n/a | n/a |
| 4 | Profile pictures | **PASS** (stand-in Cloudinary) | **NOT TESTED** | **BLOCKED** (no Cloudinary credentials/network) |
| 5 | Real AI | **PASS** (stubbed `fetch`) | **NOT TESTED** | **BLOCKED** (no network/key); Gemini request shape **not verified against current docs** (see §7) |
| 6 | App QR | **PASS** (PNG decoded with jsQR = configured URL) | **NOT TESTED** | n/a — **no store listing exists/was invented**; QR shows nothing until you configure a URL |
| 7 | Location | **PASS** | **NOT TESTED** (needs real browser permission prompt) | **BLOCKED** (no browser/GPS here) |

Honest limits: payments are online on web only; refunds are manual; live delivery tracking is **not built** (no product flow exists — decision needed); geocoding/maps are not built.

## 4. API endpoints added or modified
Added: `POST /auth/otp/send`, `POST /auth/otp/verify` (rewritten), `POST /auth/logout`, `POST /auth/logout-all`, `POST /payments/razorpay/order`, `POST /payments/razorpay/verify`, `POST /payments/razorpay/webhook`, `GET /payments/status/:orderId`, `POST|DELETE /users/me/avatar`, `POST /ai/product-description`, `GET /app/download`, `GET /app/download-qr.png`, `PATCH /businesses/:id/location`.
Modified: `POST /orders` (`paymentMethod`), `PATCH /orders/:id/status` (no `confirmed` before online payment is paid), `PATCH /users/me` (validated; `avatarUrl` no longer settable), `POST /businesses` (no default location, validated `location`), `GET /businesses`, `/businesses/nearby`, `/businesses/:id` (coarsened public location, `distanceKm`), `POST /auth/refresh` (revoked sessions refused), error handler (`Retry-After`, no raw error-code leakage).

## 5. Database and migration changes
New collections: `otptokens`, `refreshsessions`, `paymentevents`. New fields: `users.emailVerified`; `orders.payment.{amountPaise,paidAt,failureReason,needsRefund}`; `businesses.{publicLocation,locationSource}`. Removed defaults: business `location` and user-address `[0,0]`. **Migration required for existing data:** `node backend/scripts/backfill-business-locations.js` (dry-run by default, `$set` only, nothing deleted). Existing refresh tokens (no `sid`) force one re-login. Not done: unique index on `users.email`.

## 6. Environment variables
See `.env.example` (placeholders only). New: `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `OTP_HMAC_SECRET`, `RAZORPAY_KEY_ID/KEY_SECRET/WEBHOOK_SECRET`, `GEMINI_API_KEY`, `GEMINI_MODEL`, `OPENAI_API_KEY`, `OPENAI_MODEL`, `AI_TIMEOUT_MS`, `CLOUDINARY_*`, `APP_DOWNLOAD_URL`/`APP_ANDROID_URL`/`APP_IOS_URL`/`APP_WEB_URL`, `LOG_LEVEL`. Removed: `ALLOW_DEMO_OTP`.

## 7. Official documentation consulted
Consulted during this work through web search/fetch: Resend's send-email API and Node SDK reference (SDK returns `{data,error}` and does not throw on API errors; sender must be on a verified domain); Razorpay's Standard Checkout, signature-verification and webhook documentation (signature = HMAC-SHA256 of `order_id|payment_id`; webhook signature over the raw body; `x-razorpay-event-id`); Google's Gemini quickstart.
**Not verified against current docs (implemented from prior knowledge — verify before relying on them):** Gemini `generateContent` request/response shape and the default model name (the quickstart I could read documented a different, newer API; `GEMINI_MODEL` is configurable for that reason); OpenAI chat-completions JSON-schema format; Cloudinary `upload_stream` options; the Flutter packages `image_picker ^1.1.2` and `geolocator ^13.0.1` (version constraints chosen without `pub get`).
General entry points: https://resend.com/docs · https://razorpay.com/docs/ · https://ai.google.dev/gemini-api/docs · https://platform.openai.com/docs · https://cloudinary.com/documentation

## 8. Tests executed and actual results
Clean `npm ci` then: **18 suites, 312 tests, all passing**; `eslint` clean on `src`, `tests`, `scripts`. (Start of the audit: 7 tests.) New suites: OTP service + HTTP journey, payments, order/payment gating, avatar upload, AI layer, QR, location, OpenAPI drift. Key tests were **mutation-checked** — deliberately breaking the code made them fail: signature checks (verify and webhook), webhook de-duplication, amount check, ownership, paid compare-and-set, avatar type sniffing / role gate / https check / size caps (both layers removed together), AI timeout / retry limit / output validation / HTML stripping / finish-reason check, exact-location leak, owner check on location. Two mutants survived by design: a single size cap alone (the other layer still catches it) and a 67 m shift in the distance origin (hidden by the 0.1 km display rounding). Frontend: `flutter analyze/test` and `flutter build web` were **NOT RUN** (no Flutter SDK in this environment).

## 9. Evidence for end-to-end workflows
Run through the real Express app over HTTP with stand-ins at the edges only: email → send → (captured Resend payload) → verify → session → protected call → logout → refresh refused; order → Razorpay order → signed callback → verify → paid → shop may confirm; duplicate webhook → single ledger entry; upload → stored URL; QR PNG → decoded URL. **No real e-mail was delivered, no Razorpay payment was made, no AI answer was generated, no GPS position was read.** Delivery evidence tooling is provided for you to run: `scripts/send-test-email.js` and `scripts/check-resend-delivery.js`.

## 10. Bugs discovered and fixed along the way
Demo OTP back door removed entirely; OTP attempt-counting race made atomic; error handler no longer leaks raw `err.code`; logout previously did nothing server-side (now revokes sessions); profile `avatarUrl` could be any string incl. `javascript:` (now upload-only); fabricated Bengaluru default location and `[0,0]` address default removed; exact shop coordinates were public (now coarsened, distance computed on the coarse point); undocumented routes found by the drift test (`GET /businesses`, `DELETE /products/:id`) and stale docs (Firebase-first auth, refresh "rotation", `/payments/initiate`) corrected.

## 11. Remaining failures, blocked items, root causes
All BLOCKED items share one root cause: the sandbox has no route to Resend, Razorpay, Gemini/OpenAI or Cloudinary, no MongoDB and no Flutter SDK. Therefore not verified: real e-mail delivery/spam placement; Checkout.js in a browser and the `dart:js_interop` bridge; a real webhook from Razorpay; live AI answers (and the Gemini payload shape); Cloudinary uploads; geolocation prompts; **compilation of all Flutter changes**; MongoDB-level behaviour (TTL/unique/2dsphere indexes, `$near`) — queries are covered only through stubs. `npm audit --omit=dev` still reports transitive issues under `firebase-admin` (fix is a breaking major upgrade; not applied).

## 12. Missing credentials / manual steps
1. Resend: verify a domain you own; create a key; set `RESEND_FROM_EMAIL=Name <login@your-domain>`. **A Gmail sender cannot work with Resend.**
2. Razorpay Test-mode key id/secret and a webhook (URL + secret) as in `docs/payments.md`.
3. `GEMINI_API_KEY` (and a valid `GEMINI_MODEL`), or OpenAI equivalents.
4. Cloudinary credentials for avatars.
5. `APP_DOWNLOAD_URL` once a real destination exists (the deployed web URL is unknown to me; no store listing was assumed).
6. Run `cd frontend && flutter pub get && flutter analyze && flutter test && flutter build web` and fix whatever the compiler finds — expect some.
7. Run the backfill script (dry-run first) and the two Resend scripts.

## 13. Security issues identified and resolved
See §10 and `docs/security.md`. Still open: access tokens stay valid ≤15 min after logout; refresh tokens not rotated; rate limiters are per process; no unique email index; refunds manual; seller KYC "upload" is a stock-photo stand-in; Gemini/OpenAI prompt-injection is mitigated, not eliminated. **The Resend key in your task file has the shape of a real key — if it was ever real, treat it as exposed and rotate it.** It was never written into the repository (scanned: only `re_xxxx…` placeholders exist).

## 14. Production readiness
**Not ready to ship on this evidence.** Backend logic is well covered by stand-in tests, but nothing has run against real providers, a real database or a compiled Flutter app. Minimum before production: items 1–7 of §12, one real sign-in, one test-mode payment end to end (including a webhook), one AI request, one avatar upload, a Flutter build, a data backup before the migration, and a decision on refunds and delivery tracking.

## 15. Actions needing your explicit approval
Rotating/revoking the exposed key; adding a sending domain to Resend; running the backfill with `--apply`; creating the unique `users.email` index; dropping the old `businesses.location` 2dsphere index; upgrading `firebase-admin` (breaking); switching Razorpay to Live; deploying anything; deciding on delivery-partner tracking; pushing this to Git.


---

# Addendum: UI refresh, cart/checkout pop-ups, real document upload

## What was wrong
The "Upload Documents" step of entrepreneur onboarding never uploaded the owner's files. It opened a picker of **stock photos** (Pexels searches such as "identity card document") and sent those photo URLs to `POST /businesses/:id/verification-documents`, which accepted **any URL**. An application could be "verified" with a stock photo or a link the applicant did not own, and an admin had no way to open a document at all.

## What changed

| Area | Change | Status |
|---|---|---|
| Document upload (backend) | `POST /businesses/:id/documents` (multipart `file`, `type`, `identityType` for ID proofs). PDF/JPEG/PNG/WebP decided from file bytes, ≤ 5 MB, 40/hour. Stored as **private (`authenticated`) Cloudinary assets**, never a public URL. One document per type (re-upload replaces and removes the old file). Locked while in review/approved. `GET`/`DELETE` for the owner (metadata only, no storage ids). | **PASS** (18 tests incl. mutation checks) · real Cloudinary NOT TESTED |
| Submit | `POST /businesses/:id/verification-documents` now takes no body, ignores any URLs, and refuses (422 `DOCUMENTS_MISSING`) unless an ID proof and a business proof were really uploaded. | **PASS** (tests) |
| Admin access | `GET /admin/verifications/:businessId/documents/:docId/link` returns a 5-minute signed link (`Cache-Control: no-store`), admin/super_admin only. Admin screen has a **Documents** button. | **PASS** (tests) · real signed link NOT TESTED |
| OpenAPI / docs | All new routes documented; route-drift test still passes. | **PASS** |
| Flutter: theme | Gradient hero/olive canvases with soft shapes, soft shadows, floating snackbars, rounded sheets/dialogs, page transitions. | NOT TESTED (not compiled) |
| Flutter: cart | Swipe to remove (with Undo), quantity steppers, "Empty cart" confirm, coupon card, sticky total + Checkout bar, friendly empty/signed-out states, cart-count badge on the nav bar. | NOT TESTED (not compiled) |
| Flutter: add-to-cart pop-up | Quantity picker on the product page; after adding, a bottom sheet shows what was added, the cart count/total, and Keep shopping / View cart. | NOT TESTED (not compiled) |
| Flutter: order pop-up | "Confirm your order" sheet (items, delivery or pickup, payment method, exact amount) before anything is placed; "Order placed" success dialog afterwards. A payment that is not confirmed is **not** shown as success. | NOT TESTED (not compiled) |
| Flutter: orders / shop / home / profile | Status pills, 5-step order tracker, shop banner, hero header, profile header. | NOT TESTED (not compiled) |
| Flutter: documents screen | Real file picker (`file_picker`), per-document status, replace/remove, size check, privacy note, step dots (1-2-3). | NOT TESTED (not compiled) |

## Not done / limits
- No Dart/Flutter SDK was reachable in the build environment, so **none of the Flutter changes were compiled or run**. They passed only a structural (bracket/string) check and manual review. Run `flutter pub get && flutter analyze` first.
- New packages: `file_picker ^8.1.2`, `url_launcher ^6.3.0` (versions not resolved here).
- Cloudinary: PDF delivery can be restricted on new accounts (Settings → Security → "PDF and ZIP files delivery"). PDFs are uploaded as `raw` private assets and fetched through a signed download link; this has **not** been exercised against the real service.
- The optional "business profile photo" step was removed from document upload (it was a stock photo). A real shop photo/logo upload is a separate feature.
- Login, register and seller dashboard screens still use the base theme only.
- Applications already submitted with the old stock-photo "documents" keep those legacy entries (they have a `url`, no `publicId`); admins cannot open them. Ask those applicants to re-upload (reject with a reason, then they can upload again).
