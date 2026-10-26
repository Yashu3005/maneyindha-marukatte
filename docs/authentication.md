# Authentication

Sign-in is **email one-time code (OTP)**, delivered with [Resend](https://resend.com/docs). A username/password path and a Firebase ID-token exchange also exist (`/auth/login`, `/auth/firebase-exchange`) but the app's primary flow is the email code.

## Email OTP lifecycle

| Rule | Value |
|---|---|
| Code | 6 digits from Node's CSPRNG (`crypto.randomInt`) |
| Storage | only an HMAC-SHA256 hash (key: `OTP_HMAC_SECRET`, falls back to `JWT_SECRET`) in the `otptokens` collection — never the code itself |
| Expiry | 5 minutes (also enforced by a MongoDB TTL index) |
| Resend cooldown | 60 s per email (`429`, `Retry-After`, `error.retryAfterSeconds`) |
| Attempts | 5 per code; the count is spent atomically, so parallel guesses cannot exceed it |
| Single use | consumed on success; a new code replaces and invalidates any older one |
| Rate limits | per IP: 10 sends/hour; verify limited with the other auth routes |
| Comparison | constant-time |
| Responses | never contain the code. Production logs never contain the code or the full email address |
| Demo/fixed codes | **none** (the old `ALLOW_DEMO_OTP` / `029403` path was removed) |

Flow: `POST /auth/otp/send {email}` → email arrives → `POST /auth/otp/verify {email, otp}` → access token (15 min) + refresh token (30 days). The account is created on the first successful verification.

### Delivery vs "accepted"
The Resend API answering `200` with a message id means *Resend accepted* the message, not that the inbox received it. The server logs the message id; to see what happened afterwards:

```bash
cd backend
node scripts/send-test-email.js you@your-inbox.example   # sends a real test code mail, prints the Resend message id
node scripts/check-resend-delivery.js <message-id>        # asks Resend for last_event: sent | delivered | bounced | ...
```

### Providers
`EMAIL_PROVIDER=resend` (default) or `brevo`. Brevo uses its REST API (`BREVO_API_KEY`, `BREVO_FROM_EMAIL`); the sender address must be verified in the Brevo dashboard. Delivery lookup (`check-resend-delivery.js`) is Resend-only; for Brevo use Transactional → Logs in its dashboard. Brevo support is tested with a stubbed `fetch` only — no real Brevo request has been made from this repository's test environment. A free-mail sender (e.g. Gmail) on any provider can hurt inbox placement because of the sender domain's DMARC policy.

### Sender configuration (Resend)
`RESEND_FROM_EMAIL` must be an address on a **domain you have verified in Resend**. Consumer mailboxes (Gmail, Yahoo, Outlook, iCloud, Proton) cannot be used as the sender; in production the API refuses to start with one, and in development it logs a warning. For a first local test Resend documents `onboarding@resend.dev`, which only delivers to your own account email.

## Sessions and logout
- Access token: JWT, 15 minutes, stateless.
- Refresh token: JWT bound to a server-side session (`refreshsessions`, `sid`). `POST /auth/refresh` is refused once its session is revoked.
- `POST /auth/logout` revokes the session of the refresh token you send; `POST /auth/logout-all` revokes all of the user's sessions. The Flutter app calls logout before clearing local state.
- **Limit:** an access token that was already issued stays valid until it expires (≤15 min) because access tokens are not checked against the database. Refresh tokens are **not rotated** on use.
- Refresh tokens issued before sessions existed carry no `sid` and are rejected once, which forces a single re-login.

## Roles
`customer` · `entrepreneur` · `delivery_partner` · `admin` · `super_admin`. Customer ↔ entrepreneur is self-service (`POST /users/me/role`, returns fresh tokens); admin roles are never self-assignable and can never sign in through the email-code path.

## Password path
bcrypt (cost 12). Set with `POST /users/me/credentials`.
