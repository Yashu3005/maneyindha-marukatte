# Authentication Architecture

## Flow

1. **Primary identity**: Firebase Auth (phone OTP, Google, Apple, email/password)
2. Client obtains Firebase ID token → sends to `POST /auth/firebase-exchange` (Phase 2)
3. Backend verifies with firebase-admin → finds/creates `users` doc → issues its own **JWT pair**:
   - access token (15 min) — sent as `Authorization: Bearer`
   - refresh token (30 days) — rotated on use
4. Role stored in JWT payload; `requireRole()` middleware enforces RBAC per route.

## Why exchange Firebase tokens for our own JWTs?

- Role/permission claims live in our DB, not Firebase custom claims
- Backend stays provider-independent (spec's future-readiness requirement)
- Short-lived access tokens limit blast radius

## Roles

`customer` · `entrepreneur` · `delivery_partner` · `admin` · `super_admin`

Role selection at signup for the first three; admin roles are provisioned
manually / by super_admin only — never self-assignable via the API.

## Password path (fallback)

bcrypt cost 12, min 8 chars, hash stored with `select: false`.
