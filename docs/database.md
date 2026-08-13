# Database Schema (MongoDB Atlas)

## Implemented collections (Phase 1)

- **users** — all roles in one collection, `role` discriminator. Geo index on addresses. Soft delete via `deletedAt`.
- **businesses** — 2dsphere index on `location` for nearby search, text index on name/description, embedded verification workflow.
- **products** — text index for search, embedded variants, stock + low-stock threshold.
- **orders** — item snapshots (name/price at purchase time), state machine with `statusHistory` audit trail, payment sub-document.
- **categories** — self-referencing `parent` for subcategories.

## Remaining collections (build per phase)

payments, transactions, wallets, coupons, reviews, wishlist, carts,
inventoryLogs, notifications, stories, communityPosts, followers,
messages/chats, reports, supportTickets, invoices, bankAccounts,
verificationDocuments, loyaltyPoints, rewardHistory, referralHistory, settings.

## Conventions

- `timestamps: true` on every schema
- Soft delete: `deletedAt: Date|null`, filter `isActive: true` in queries
- Geo: GeoJSON `Point`, coordinates as `[lng, lat]`
- Money: store as integer paise in Phase 8 (avoid float rounding) — current Number fields are placeholders
- Indexes: every foreign key gets an index; compound indexes added per query pattern
