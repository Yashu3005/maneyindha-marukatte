# System Architecture

## High-level diagram

```
                        ┌────────────────────────────┐
                        │        Clients             │
                        │  Flutter (Android/iOS/Web) │
                        │  Admin Web (responsive)    │
                        └─────────────┬──────────────┘
                                      │ HTTPS / WSS
                 ┌────────────────────┼─────────────────────┐
                 │                    │                     │
        ┌────────▼────────┐  ┌────────▼────────┐   ┌────────▼────────┐
        │  Vercel          │  │  Node/Express   │   │  Socket.IO      │
        │  Flutter Web +   │  │  REST API v1    │   │  (Railway/      │
        │  Admin dashboard │  │  (Railway/      │   │   Render — NOT  │
        │                  │  │   Render)       │   │   Vercel)       │
        └──────────────────┘  └───┬────┬───┬────┘   └────────┬────────┘
                                  │    │   │                 │
              ┌───────────────────┘    │   └──────────┐      │
     ┌────────▼───────┐   ┌────────────▼──┐  ┌────────▼──────▼─┐
     │ MongoDB Atlas  │   │ Redis (managed│  │ Firebase        │
     │ (primary data) │   │ Upstash/Redis │  │ Auth + FCM +    │
     │                │   │ Cloud): cache,│  │ Storage         │
     └────────────────┘   │ sessions, rate│  └─────────────────┘
                          │ limits        │
                          └───────────────┘
     ┌────────────────┐   ┌───────────────┐  ┌─────────────────┐
     │ Cloudinary     │   │ Razorpay      │  │ AI provider     │
     │ (media CDN)    │   │ (payments +   │  │ (Gemini/OpenAI, │
     │                │   │  webhooks)    │  │  swappable)     │
     └────────────────┘   └───────────────┘  └─────────────────┘
```

## Key decisions

1. **Vercel hosts web frontends only.** The Express API needs persistent
   WebSocket connections (live order tracking, chat) and background jobs —
   deploy it on Railway/Render/Fly.io. Do not force it into Vercel
   serverless functions (spec §40).
2. **One shared Flutter codebase** for Android, iOS, web, tablet.
   Feature-based clean architecture: presentation → domain → data.
3. **Layered backend**: routes → controllers → services → repositories/models.
   Business logic lives in services; routes stay thin.
4. **Order lifecycle is a server-enforced state machine**
   (`models/Order.js` → `VALID_TRANSITIONS`). Invalid transitions return 422.
5. **AI layer is provider-agnostic** (`src/ai/`). Switching Gemini↔OpenAI
   is an env-var change, not a rewrite.
6. **Payments are verified server-side only.** Razorpay signature
   verification + webhooks; client-reported payment status is never trusted.

## Scaling path

| Stage | Action |
|---|---|
| 0–1k users | Single API instance, Atlas M0/M2, Upstash free Redis |
| 1k–10k | Horizontal API replicas behind LB, Redis caching hot queries, CDN images |
| 10k–100k | Read replicas, queue-based jobs (BullMQ), dedicated search (Atlas Search/Meilisearch), FCM topic fanout |
| 100k+ | Service extraction (orders, search, notifications), sharding by region |
