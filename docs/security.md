# Security Checklist

## Implemented in skeleton
- helmet, CORS allowlist, express-mongo-sanitize (NoSQL injection), rate limiting
- JWT access/refresh split, bcrypt(12), RBAC middleware
- Centralized error handler — stack traces never reach clients
- Joi input validation, ownership checks on entrepreneur writes
- Order state machine prevents invalid transitions
- Server-side pricing — client totals ignored

## Phase 17 hardening
- Tighter rate limits on /auth/* (brute-force)
- Refresh-token rotation with revocation list in Redis
- Admin: 2FA, IP audit log, sensitive-action re-auth
- File upload: type sniffing (magic bytes), size caps, Cloudinary signed uploads
- CSP headers for web, dependency audit in CI (npm audit / Snyk)
- Razorpay webhook signature verification, replay protection
- Secrets only in env vars / Vercel envs — never in repo (enforced by .gitignore)
