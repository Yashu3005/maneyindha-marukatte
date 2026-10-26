#!/usr/bin/env node
/*
 * One-off, NON-destructive migration for shops created before the location rework.
 *
 *  - Shops whose stored point is exactly the old hard-coded placeholder (Bengaluru city centre, 77.5946/12.9716)
 *    were never real locations: they are marked locationSource="unset" and left OUT of "near me" until the
 *    owner sets a real location. Their stored `location` is left untouched (nothing is deleted).
 *  - Shops with any other valid point get the derived `publicLocation` (coarsened) and locationSource="manual".
 *
 * DRY RUN by default. Pass --apply to write. Only $set is used; no deletes, no drops.
 *   node scripts/backfill-business-locations.js            # report only
 *   node scripts/backfill-business-locations.js --apply    # write
 */
const mongoose = require('mongoose');
const { loadEnv } = require('../src/config/env');
const { isValidLatLng, coarsen } = require('../src/utils/geo');

loadEnv();
const PLACEHOLDER = [77.5946, 12.9716];
const apply = process.argv.includes('--apply');

(async () => {
  if (!process.env.MONGODB_URI) { console.error('MONGODB_URI is not set'); process.exit(1); }
  await mongoose.connect(process.env.MONGODB_URI);
  const col = mongoose.connection.collection('businesses');
  const counts = { placeholder: 0, backfilled: 0, alreadyDone: 0, invalid: 0 };
  for await (const b of col.find({ locationSource: { $exists: false } })) {
    const c = b.location?.coordinates;
    let update;
    if (!Array.isArray(c) || c.length !== 2 || !isValidLatLng(c[1], c[0])) { counts.invalid += 1; update = { locationSource: 'unset' }; }
    else if (c[0] === PLACEHOLDER[0] && c[1] === PLACEHOLDER[1]) { counts.placeholder += 1; update = { locationSource: 'unset' }; }
    else { counts.backfilled += 1; update = { locationSource: 'manual', publicLocation: { type: 'Point', coordinates: coarsen(c) } }; }
    if (apply) await col.updateOne({ _id: b._id }, { $set: update });
  }
  counts.alreadyDone = await col.countDocuments({ locationSource: { $exists: true } });
  console.log(`${apply ? 'APPLIED' : 'DRY RUN (nothing written)'}:`, JSON.stringify(counts));
  await mongoose.disconnect();
})().catch((e) => { console.error(`Failed: ${e.message}`); process.exit(1); });
