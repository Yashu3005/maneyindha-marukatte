#!/usr/bin/env node
/*
 * Shop photo check / safe repair. DRY RUN by default: it only READS and prints a report.
 *
 *   node scripts/check-shop-photos.js            # report only
 *   node scripts/check-shop-photos.js --apply    # also clear values that are not real https URLs
 *
 * Reports how many active shops have a usable picture (cover, logo or gallery), which have none, and which have a
 * stored value that is not a valid https URL (broken data). --apply only clears those invalid values ($unset on
 * bannerUrl/logoUrl, invalid gallery entries removed) so the app shows its placeholder instead of a broken image.
 * It never invents or guesses a photo URL: shops without a photo get one when their owner uploads it
 * (Profile -> Shop photo).
 */
const mongoose = require('mongoose');
const { loadEnv } = require('../src/config/env');
const { coverOf, isHttps } = require('../src/utils/shopPhoto');

loadEnv();
const apply = process.argv.includes('--apply');

(async () => {
  if (!process.env.MONGODB_URI) { console.error('MONGODB_URI is not set'); process.exit(1); }
  await mongoose.connect(process.env.MONGODB_URI);
  const col = mongoose.connection.collection('businesses');
  const counts = { shops: 0, withPhoto: 0, withoutPhoto: 0, withInvalidValues: 0 };
  const needPhoto = [];
  for await (const b of col.find({ isActive: { $ne: false } })) {
    counts.shops += 1;
    if (coverOf(b)) counts.withPhoto += 1; else { counts.withoutPhoto += 1; needPhoto.push(b.name); }
    const bad = {};
    if (b.bannerUrl && !isHttps(b.bannerUrl)) bad.bannerUrl = '';
    if (b.logoUrl && !isHttps(b.logoUrl)) bad.logoUrl = '';
    const gallery = Array.isArray(b.gallery) ? b.gallery : [];
    const goodGallery = gallery.filter(isHttps);
    if (Object.keys(bad).length || goodGallery.length !== gallery.length) {
      counts.withInvalidValues += 1;
      if (apply) {
        const update = { $unset: bad };
        if (goodGallery.length !== gallery.length) update.$set = { gallery: goodGallery };
        if (!Object.keys(bad).length) delete update.$unset;
        await col.updateOne({ _id: b._id }, update);
      }
    }
  }
  console.log(`${apply ? 'APPLIED' : 'DRY RUN (nothing written)'}:`, JSON.stringify(counts));
  if (needPhoto.length) console.log('Shops with no photo (owners can add one under Profile > Shop photo):', needPhoto.join(', '));
  await mongoose.disconnect();
})().catch((e) => { console.error(`Failed: ${e.message}`); process.exit(1); });
