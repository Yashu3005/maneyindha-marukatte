# Location

Principles: location is **permission-based, optional, and never invented**.

## Customers
- The home screen's **Near me** button explains why, then asks the browser/device for one position (`geolocator`). Denied, switched off, timed out or unavailable → a clear message and the normal all-shops list (manual browsing). Nothing is stored server-side; the position is only sent as query parameters to `GET /businesses/nearby`.
- Results carry `distanceKm` (0.1 km resolution).

## Shops
- Owners can attach the device location during onboarding (optional) or later with `PATCH /businesses/:id/location {lat,lng,source:"device"|"manual"}` (owner only).
- **No default location.** The old hard-coded Bengaluru point was removed; a shop that never shared a location has `locationSource:"unset"`, is still listed in `GET /businesses`, but is not returned by `nearby`.
- **Privacy.** The exact point (`location`) is visible to the owner and admins only. Public endpoints return a coarsened point (`publicLocation`, 3 decimal places ≈ 110 m) under the same `location` field name, and `nearby` searches and measures distance on that coarse point, so repeated queries cannot be used to recover the exact position.

## Validation (server)
GeoJSON `[lng, lat]`, finite numbers, lat ∈ [−90, 90], lng ∈ [−180, 180], and `(0,0)` ("null island", the typical unset value) is rejected — for shop locations, saved addresses (`PATCH /users/me`) and order delivery addresses. Saved addresses may omit coordinates entirely (manual entry).

## Migration for existing data
`node scripts/backfill-business-locations.js` (dry-run) / `--apply`. It marks shops still on the old placeholder point as `unset` (nothing is deleted) and derives `publicLocation` for the others. Old shops without `publicLocation` do not appear in `nearby` until migrated.

## Not implemented
- **Live delivery tracking / delivery-partner GPS.** The product has no delivery-partner assignment flow, so there is nothing real to track. Showing a moving dot would be simulated, and is deliberately not done. This needs a product decision (who delivers, how partners are assigned and consent to tracking).
- **Address → coordinates (geocoding) and map display** — would need a maps provider key (`GOOGLE_MAPS_API_KEY` is reserved but unused).
- Delivery-radius enforcement at checkout.
