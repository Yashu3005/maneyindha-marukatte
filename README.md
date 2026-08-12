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
| Auth | Firebase Auth → backend JWT exchange |
| Payments | Razorpay (UPI, cards, wallets, COD) |
| Media | Cloudinary + Firebase Storage |
| Maps | Google Maps Platform |
| AI | Provider-agnostic layer (Gemini / OpenAI) |
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
cp .env.example .env   # fill in MongoDB, JWT secrets at minimum

# 3. Local infrastructure
docker compose up -d mongo redis

# 4. Backend
cd backend && npm install && npm run dev   # http://localhost:5000/health

# 5. Frontend
cd ../frontend && flutter pub get && flutter run -d chrome
```

## Testing
```bash
cd backend && npm test && npm run lint
cd frontend && flutter analyze && flutter test
```

## Deployment
- Web → Vercel via GitHub integration (`main` = production, PRs = previews)
- API → Railway/Render (persistent WebSockets — see `docs/deployment.md`)
- Never commit secrets; use Vercel/host env vars (`docs/security.md`)

## Documentation
See [`docs/`](docs/) — architecture, database, API, auth, payments, deployment, GitHub workflow, security, AI, testing, roadmap.

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
