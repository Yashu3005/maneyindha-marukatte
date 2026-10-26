# Deployment

## Topology

| Component | Where | Why |
|---|---|---|
| Flutter web + admin | **Vercel** (GitHub integration) | static/edge hosting, preview deploys per PR |
| Express API + Socket.IO | Railway / Render / Fly.io | persistent WebSockets + background jobs (Vercel serverless can't) |
| MongoDB | Atlas | managed, backups |
| Redis | Upstash / Redis Cloud | managed |
| Media | Cloudinary + Firebase Storage | CDN + transforms |

## Vercel setup

1. Import GitHub repo in Vercel → set root directory to the web build output
2. Production branch: `main`; every PR gets a preview URL
3. Environment variables per environment (Development/Preview/Production) — see `.env.example`
4. Flutter web build command: `flutter build web --release --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1`

## Local dev

```bash
git clone <repo> && cd maneyindha-marukatte
cp .env.example .env          # fill in values
docker compose up mongo redis # local deps
cd backend && npm install && npm run dev
cd ../frontend && flutter pub get && flutter run -d chrome
```

## Production checklist (new features)
- `NODE_ENV=production` makes the API refuse to start without strong JWT secrets and a valid Resend configuration (`RESEND_API_KEY`, `RESEND_FROM_EMAIL` on a verified domain).
- Razorpay: Test keys first. Register the webhook URL `https://<api>/api/v1/payments/razorpay/webhook` and set `RAZORPAY_WEBHOOK_SECRET`. The API must receive the **raw** body (no body-rewriting proxy).
- Run `node scripts/backfill-business-locations.js` (dry-run first) once on existing databases.
- Set `APP_DOWNLOAD_URL` (or `APP_WEB_URL`/`APP_ANDROID_URL`/`APP_IOS_URL`) to a real public https destination to show the landing-page QR; leave empty to hide it.
- Cloudinary variables enable profile-photo upload; without them the endpoint answers 503 and the default avatar is used.
- Rate limiters are per-process; use a shared store when scaling out.
