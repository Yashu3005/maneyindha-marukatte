# Security

## In place
- helmet, CORS allow-list (`CORS_ORIGINS`), express-mongo-sanitize, global rate limit (500/15 min) plus tighter limits on auth, OTP send, AI, uploads and payments
- JWT access (15 min) / refresh (30 days) with server-side session revocation; bcrypt(12); RBAC middleware; ownership checks on writes
- Email OTP: CSPRNG, keyed hash only, expiry, cooldown, attempt limit, single use (see `authentication.md`)
- Razorpay: server-side amounts, HMAC signature verification in constant time, raw-body webhook verification, event de-duplication, ownership checks (see `payments.md`)
- Uploads: avatars are accepted only for entrepreneurs, ≤ 2 MB, JPEG/PNG/WebP decided by magic bytes (declared type ignored), memory storage, stored on Cloudinary under a per-user id; `avatarUrl` cannot be set through `PATCH /users/me`
- Location: coordinate validation, exact shop location private to owner/admins (see `location.md`)
- AI: product text only is sent to providers, output validated and sanitised, per-user limit
- Centralised error handler: no stack traces, no provider messages, no `err.code` leaks
- Secrets only in environment variables (`.env.example` holds placeholders); logs never include OTPs, API keys or request bodies of AI/payment calls

## Known limits / recommendations
- Access tokens are not revocable before expiry (≤15 min); refresh tokens are not rotated.
- `users.email` has no unique index in the schema — add one after de-duplicating existing data.
- Rate limiters use per-process memory; use a shared store (e.g. Redis) when running several instances.
- Refunds of paid online orders are manual (`payment.needsRefund`).
- Seller "document upload" in onboarding still stores picked stock-photo URLs, not real KYC uploads — do not rely on it as identity verification.
- If a live API key was ever pasted into a chat, ticket or commit, treat it as exposed and **rotate it**.
- CI dependency audit, CSP for the web build and admin 2FA remain future work.
