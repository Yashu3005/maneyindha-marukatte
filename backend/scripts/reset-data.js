#!/usr/bin/env node
/* Removes ALL customer and entrepreneur data so the app can start fresh.
 *
 *   npm run reset:data                                   -> DRY RUN: only counts what would be removed
 *   npm run reset:data -- --apply --confirm=<db name>    -> really deletes (asks you to type DELETE)
 *
 * Safety:
 *  - Dry run by default; nothing is touched without --apply.
 *  - --confirm must equal the exact database name shown, and you must type DELETE at the prompt.
 *  - Everything that will be deleted is first saved to backend/backups/<timestamp>/ (password hashes and
 *    security answers are never included). That folder holds personal data: keep it private, delete it when no
 *    longer needed. It is git-ignored.
 *  - The single administrator account (ADMIN_USERNAME) is kept. Categories and reward coupons are kept unless
 *    you pass --include-categories / --include-coupons.
 *  - Files stored at Cloudinary (documents, profile photos, shop videos) are left alone unless you pass
 *    --purge-uploads.
 *  - It never drops collections or indexes.
 */
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const ADMIN_ROLES = ['admin', 'super_admin'];

// What to remove. `filter(adminId)` always excludes the administrator.
function buildPlan(models, { adminId, includeCategories = false, includeCoupons = false } = {}) {
  const notAdminUser = adminId ? { user: { $ne: adminId } } : {};
  const plan = [
    { name: 'users', Model: models.User, filter: adminId ? { _id: { $ne: adminId } } : {} },
    { name: 'businesses', Model: models.Business, filter: {} },
    { name: 'products', Model: models.Product, filter: {} },
    { name: 'orders', Model: models.Order, filter: {} },
    { name: 'carts', Model: models.Cart, filter: {} },
    { name: 'reviews', Model: models.Review, filter: {} },
    { name: 'wishlists', Model: models.Wishlist, filter: {} },
    { name: 'notifications', Model: models.Notification, filter: notAdminUser },
    { name: 'transactions', Model: models.Transaction, filter: notAdminUser },
    { name: 'wallets', Model: models.Wallet, filter: notAdminUser },
    { name: 'paymentevents', Model: models.PaymentEvent, filter: {} },
    { name: 'otptokens', Model: models.OtpToken, filter: {} },
    { name: 'refreshsessions', Model: models.RefreshSession, filter: notAdminUser },
  ];
  if (includeCategories) plan.push({ name: 'categories', Model: models.Category, filter: {} });
  if (includeCoupons) plan.push({ name: 'coupons', Model: models.Coupon, filter: {} });
  return plan;
}

// Remote files that belong to the data being removed (ids only; nothing is fetched).
function collectUploads({ businesses = [], users = [] }) {
  const out = [];
  for (const b of businesses) {
    for (const d of b.verification?.documents || []) {
      if (d.publicId) out.push({ publicId: d.publicId, resourceType: d.resourceType === 'raw' ? 'raw' : 'image', type: 'authenticated' });
    }
    if (b.promoVideo?.publicId) out.push({ publicId: b.promoVideo.publicId, resourceType: 'video', type: 'upload' });
  }
  for (const u of users) {
    if (u.avatarUrl) out.push({ publicId: `avatars/user_${u._id}`, resourceType: 'image', type: 'upload' });
  }
  return out;
}

function confirmationProblem(args, dbName) {
  if (!args.apply) return null;
  if (args.confirm !== dbName) return `--confirm must be exactly the database name shown above ("${dbName}")`;
  return null;
}

function parseArgs(argv) {
  const args = { apply: false, confirm: null, includeCategories: false, includeCoupons: false, purgeUploads: false };
  for (const a of argv) {
    if (a === '--apply') args.apply = true;
    else if (a.startsWith('--confirm=')) args.confirm = a.slice('--confirm='.length);
    else if (a === '--include-categories') args.includeCategories = true;
    else if (a === '--include-coupons') args.includeCoupons = true;
    else if (a === '--purge-uploads') args.purgeUploads = true;
    else throw new Error(`Unknown option: ${a}`);
  }
  return args;
}

const ask = (q) => new Promise((resolve) => {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  rl.question(q, (a) => { rl.close(); resolve(a); });
});

async function backup(plan, dir) {
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  for (const { name, Model, filter } of plan) {
    const file = path.join(dir, `${name}.jsonl`);
    const out = fs.createWriteStream(file, { mode: 0o600 });
    let n = 0;
    for await (const doc of Model.find(filter).lean().cursor()) { out.write(`${JSON.stringify(doc)}\n`); n += 1; }
    await new Promise((r) => out.end(r));
    console.log(`  saved ${String(n).padStart(6)}  ${name}`);
  }
}

async function purgeUploads(uploads) {
  const { v2: cloudinary } = require('cloudinary');
  cloudinary.config({ cloud_name: process.env.CLOUDINARY_CLOUD_NAME, api_key: process.env.CLOUDINARY_API_KEY, api_secret: process.env.CLOUDINARY_API_SECRET, secure: true });
  const groups = new Map();
  for (const u of uploads) {
    const k = `${u.resourceType}|${u.type}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(u.publicId);
  }
  for (const [k, ids] of groups) {
    const [resource_type, type] = k.split('|');
    for (let i = 0; i < ids.length; i += 100) {
      await cloudinary.api.delete_resources(ids.slice(i, i + 100), { resource_type, type, invalidate: true });
    }
    console.log(`  removed ${ids.length} ${resource_type} file(s) from Cloudinary`);
  }
}

async function main() {
  require('./../src/config/env').loadEnv();
  const args = parseArgs(process.argv.slice(2));
  if (!process.env.MONGODB_URI) throw new Error('MONGODB_URI is not set');
  const mongoose = require('mongoose');
  const models = {
    User: require('../src/models/User'), Business: require('../src/models/Business'), Product: require('../src/models/Product'),
    Order: require('../src/models/Order'), Cart: require('../src/models/Cart'), Review: require('../src/models/Review'),
    Wishlist: require('../src/models/Wishlist'), Notification: require('../src/models/Notification'),
    Transaction: require('../src/models/Transaction'), Wallet: require('../src/models/Wallet'),
    PaymentEvent: require('../src/models/PaymentEvent'), OtpToken: require('../src/models/OtpToken'),
    RefreshSession: require('../src/models/RefreshSession'), Category: require('../src/models/Category'), Coupon: require('../src/models/Coupon'),
  };

  await mongoose.connect(process.env.MONGODB_URI);
  const dbName = mongoose.connection.name;
  console.log(`\nDatabase: ${mongoose.connection.host} / ${dbName}`);
  console.log(args.apply ? 'Mode: APPLY (will delete)\n' : 'Mode: DRY RUN (nothing will be changed)\n');

  const adminName = String(process.env.ADMIN_USERNAME || '').trim().toLowerCase();
  const admin = adminName ? await models.User.findOne({ username: adminName, role: { $in: ADMIN_ROLES } }).select('_id') : null;
  console.log(admin ? `Keeping the administrator account "${adminName}".` : 'No administrator account found in this database to keep (it is created again on the next admin sign-in).');

  const plan = buildPlan(models, { adminId: admin?._id, includeCategories: args.includeCategories, includeCoupons: args.includeCoupons });
  console.log('\nWould remove:');
  let total = 0;
  for (const p of plan) {
    p.count = await p.Model.countDocuments(p.filter);
    total += p.count;
    console.log(`  ${String(p.count).padStart(6)}  ${p.name}`);
  }
  console.log(`  ------\n  ${String(total).padStart(6)}  documents in total`);

  const ownerFilter = admin ? { _id: { $ne: admin._id } } : {};
  const shops = await models.Business.find({}).select('verification.documents promoVideo.publicId').lean();
  const people = await models.User.find({ ...ownerFilter, avatarUrl: { $exists: true } }).select('avatarUrl').lean();
  const uploads = collectUploads({ businesses: shops, users: people });
  console.log(`\nUploaded files at Cloudinary linked to this data: ${uploads.length}${args.purgeUploads ? ' (will be deleted)' : ' (will be left in place; add --purge-uploads to delete them)'}`);

  if (!args.apply) {
    console.log(`\nDRY RUN complete. Nothing was changed.\nTo delete for real:\n  npm run reset:data -- --apply --confirm=${dbName}\n`);
    return mongoose.disconnect();
  }

  const problem = confirmationProblem(args, dbName);
  if (problem) throw new Error(problem);
  if (!process.stdin.isTTY) throw new Error('Run this in a terminal: it asks you to type DELETE to continue.');
  const answer = await ask(`\nThis permanently removes the ${total} documents above from "${dbName}". Type DELETE to continue: `);
  if (answer.trim() !== 'DELETE') { console.log('Cancelled. Nothing was changed.'); return mongoose.disconnect(); }

  const dir = path.resolve(__dirname, '..', 'backups', `reset-${new Date().toISOString().replace(/[:.]/g, '-')}`);
  console.log(`\nBacking up to ${dir} …`);
  await backup(plan, dir);

  console.log('\nDeleting …');
  for (const p of plan) {
    const r = await p.Model.deleteMany(p.filter);
    console.log(`  deleted ${String(r.deletedCount).padStart(6)}  ${p.name}`);
  }
  if (args.purgeUploads && uploads.length) await purgeUploads(uploads);

  console.log('\nRemaining:');
  for (const p of plan) console.log(`  ${String(await p.Model.countDocuments({})).padStart(6)}  ${p.name}`);
  console.log(`\nDone. A backup of what was removed is in ${dir}\n`);
  await mongoose.disconnect();
}

module.exports = { buildPlan, collectUploads, confirmationProblem, parseArgs };

if (require.main === module) {
  main().catch((e) => { console.error(`\nStopped: ${e.message}\n`); process.exit(1); });
}
