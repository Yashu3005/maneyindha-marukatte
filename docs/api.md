# API Architecture

Base: `/api/v1` — JWT bearer auth — consistent envelope:

```json
{ "success": true,  "data": ..., "meta": { "page": 1, "limit": 20, "total": 123 } }
{ "success": false, "error": { "message": "...", "code": "..." } }
```

## Implemented (Phase 1 skeleton)

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | /auth/register | – | email or phone + password |
| POST | /auth/login | – | returns access + refresh tokens |
| POST | /auth/refresh | – | rotate tokens |
| GET | /businesses/nearby?lat=&lng=&radiusKm= | – | geo query, approved businesses only |
| GET | /businesses/:id | – | |
| POST | /businesses | entrepreneur | |
| GET | /products?q=&category=&page=&limit=&sort= | – | text search + pagination |
| GET | /products/:id | – | |
| POST | /products | entrepreneur | ownership enforced |
| POST | /orders | customer | server-side pricing, stock check |
| GET | /orders/mine | any | role-scoped |
| PATCH | /orders/:id/status | any* | state-machine validated (*role guards per transition in Phase 3) |

## Standards

- Joi validation on every write endpoint (422 on failure)
- Rate limiting: global 500/15min; tighten auth endpoints in Phase 17
- Swagger/OpenAPI: mount `swagger-ui-express` at `/api/docs` in Phase 3
- Versioning: breaking changes → `/api/v2`
