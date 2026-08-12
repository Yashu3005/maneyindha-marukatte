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
