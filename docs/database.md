# Database Schema (MongoDB Atlas)

## Implemented collections (Phase 1)

- **users** — all roles in one collection, `role` discriminator. Geo index on addresses. Soft delete via `deletedAt`.
- **businesses** — `location` (exact; owner/admin only, absent until set) and `publicLocation` (≈110 m, 2dsphere-indexed, used by `nearby`) plus `locationSource`;  text index on name/description, embedded verification workflow.
- **products** — text index for search, embedded variants, stock + low-stock threshold.
- **orders** — item snapshots (name/price at purchase time), state machine with `statusHistory` audit trail, payment sub-document.
- **categories** — self-referencing `parent` for subcategories.

## Added with the OTP / payments work
- **otptokens** — hashed one-time codes (TTL index on `expiresAt`, unique per email+purpose)
- **refreshsessions** — revocable refresh sessions (`sid`), TTL on expiry
- **paymentevents** — processed Razorpay webhook event ids (unique, 90-day TTL)
- **orders.payment** — `method`, `status`, `razorpayOrderId`, `razorpayPaymentId`, `amountPaise`, `paidAt`, `failureReason`, `needsRefund`
- **users** — `emailVerified`; `avatarUrl` is written only by the avatar endpoint; address `location` has no default

Notes: `users.email` is not a unique index (add one after de-duplicating). A leftover 2dsphere index on `businesses.location` from older deployments is harmless and can be dropped manually.

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
