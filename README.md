# 🌸 Maneyindha Marukatte

**Empowering Home-Based Women Entrepreneurs** — a localized marketplace connecting nearby customers with trusted home-based women entrepreneurs (baking, tailoring, handicrafts, tiffin services, mehendi, and more).

## Problem
Home-based women entrepreneurs rely on WhatsApp, Instagram, and word-of-mouth — no discoverability, no payments, no order management, no trust signals.

## Solution
A cross-platform marketplace (Android / iOS / Web / PWA) with verified business profiles, nearby discovery, secure payments, delivery tracking, community features, and AI-powered business insights.

## Tech Stack
| Layer | Tech |
|---|---|
| Mobile/Web app | Flutter, Riverpod, Material 3, go_router |
| Backend | Node.js, Express, Socket.IO |
| Database | MongoDB Atlas + Redis |
| Auth | Email one-time code via Resend → backend JWT (+ revocable refresh sessions) |
| Payments | Razorpay Standard Checkout (test mode first) + cash on delivery |
| Media | Cloudinary (profile photos); optional Pexels stock suggestions |
| Location | Device geolocation (permission-based) + server-side distance; no maps provider yet |
| AI | Provider-agnostic layer: Gemini (default) / OpenAI over REST |
| Deploy | Vercel (web) + Railway/Render (API) |

## Repository Structure
```
maneyindha-marukatte/
├── frontend/        Flutter app (Android/iOS/Web/tablet)
├── backend/         Express REST API + Socket.IO
├── admin/           Admin web dashboard (Phase 6)
├── docs/            Architecture, API, DB, security, deployment docs
├── .github/         CI/CD workflows
├── docker-compose.yml
└── .env.example
```

## Quick Start
```bash
# 1. Clone
git clone https://github.com/<you>/maneyindha-marukatte.git
cd maneyindha-marukatte

# 2. Environment
cp .env.example .env   # MongoDB + JWT secrets are required; Resend is required to sign in (see below)

# 3. Local infrastructure
docker compose up -d mongo redis

# 4. Backend
cd backend && npm install && npm run dev   # http://localhost:5000/health (PORT in .env)

# 5. Frontend (the app defaults to http://localhost:5050/api/v1 — set PORT=5050 in .env,
#    or pass --dart-define=API_BASE_URL=http://localhost:5000/api/v1)
cd ../frontend && flutter pub get && flutter run -d chrome
```

## Feature setup (all optional except email sign-in)
| Feature | What you need | Details |
|---|---|---|
| Email sign-in | `RESEND_API_KEY` + `RESEND_FROM_EMAIL` on a **verified domain** (Gmail addresses cannot send) | [`docs/authentication.md`](docs/authentication.md) |
| Online payment | Razorpay **test** keys + webhook secret | [`docs/payments.md`](docs/payments.md) |
| Product descriptions by AI | `GEMINI_API_KEY` (or `AI_PROVIDER=openai` + `OPENAI_API_KEY`) | [`docs/ai.md`](docs/ai.md) |
| Profile photos | `CLOUDINARY_*` | [`docs/security.md`](docs/security.md) |
| Landing-page QR | `APP_DOWNLOAD_URL` (or `APP_WEB_URL` / `APP_ANDROID_URL` / `APP_IOS_URL`), public https only | [`docs/deployment.md`](docs/deployment.md) |
| Near me | none (browser/device permission) | [`docs/location.md`](docs/location.md) |

API reference: `/api/docs` (Swagger UI) and [`backend/src/docs/openapi.json`](backend/src/docs/openapi.json). What was and was not verified: [`docs/IMPLEMENTATION_REPORT.md`](docs/IMPLEMENTATION_REPORT.md).

## Testing
```bash
cd backend && npm ci && npm test && npm run lint
cd frontend && flutter analyze && flutter test
```

## Deployment
- Web → Vercel via GitHub integration (`main` = production, PRs = previews)
- API → Railway/Render (persistent WebSockets — see `docs/deployment.md`)
- Never commit secrets; use Vercel/host env vars (`docs/security.md`)

## Documentation
See [`docs/`](docs/) — architecture, database, API, auth, payments, location, deployment, GitHub workflow, security, AI, testing, roadmap, and the audit and implementation reports.

## Branch Workflow
`feature/*` → PR → `develop` → release PR → `main` → production deploy.
Conventional commits (`feat:`, `fix:`, `docs:`, `test:`).

## Roadmap
See [`docs/roadmap.md`](docs/roadmap.md). Current status: **M1 (Foundation) complete** — auth exchange and remaining models are next.

## Contributing
1. Branch from `develop`
2. Follow the layered architecture (routes → controllers → services → models)
3. Add tests for services and endpoints
4. Open a PR; CI must be green

## License
TBD (MIT recommended before public release).
