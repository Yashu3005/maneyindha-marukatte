// The data-reset script's decisions (what is targeted, what is kept, what it refuses). It is never run against a database here.
const { buildPlan, collectUploads, confirmationProblem, parseArgs } = require('../scripts/reset-data');
const { oid } = require('./helpers');

const models = Object.fromEntries(['User', 'Business', 'Product', 'Order', 'Cart', 'Review', 'Wishlist', 'Notification',
  'Transaction', 'Wallet', 'PaymentEvent', 'OtpToken', 'RefreshSession', 'Category', 'Coupon'].map((n) => [n, { modelName: n }]));

describe('buildPlan', () => {
  const adminId = oid();
  const plan = (opts) => buildPlan(models, { adminId, ...opts });
  const byName = (p, n) => p.find((x) => x.name === n);

  test('covers every customer / entrepreneur collection', () => {
    expect(plan().map((p) => p.name)).toEqual(['users', 'businesses', 'products', 'orders', 'carts', 'reviews', 'wishlists',
      'notifications', 'transactions', 'wallets', 'paymentevents', 'otptokens', 'refreshsessions']);
  });
  test('the administrator is excluded from users and from everything keyed by user', () => {
    const p = plan();
    expect(byName(p, 'users').filter).toEqual({ _id: { $ne: adminId } });
    for (const n of ['notifications', 'transactions', 'wallets', 'refreshsessions']) expect(byName(p, n).filter).toEqual({ user: { $ne: adminId } });
  });
  test('no admin known -> everything is targeted with empty filters', () => {
    const p = buildPlan(models, {});
    expect(byName(p, 'users').filter).toEqual({});
    expect(byName(p, 'refreshsessions').filter).toEqual({});
  });
  test('categories and coupons are kept unless asked for', () => {
    expect(plan().some((p) => ['categories', 'coupons'].includes(p.name))).toBe(false);
    const p = plan({ includeCategories: true, includeCoupons: true });
    expect(p.slice(-2).map((x) => x.name)).toEqual(['categories', 'coupons']);
  });
  test('each target points at the right model', () => {
    for (const t of plan()) expect(t.Model).toBeDefined();
    expect(byName(plan(), 'orders').Model).toBe(models.Order);
  });
});

describe('collectUploads', () => {
  test('lists private documents (by file kind), promo videos and avatars; ignores legacy URL-only documents', () => {
    const u1 = oid(); const u2 = oid();
    const out = collectUploads({
      businesses: [
        { verification: { documents: [{ type: 'id_proof', publicId: 'verification/a', resourceType: 'image' }, { type: 'business_proof', publicId: 'verification/b', resourceType: 'raw' }, { type: 'other', url: 'https://stock/x.jpg' }] },
          promoVideo: { publicId: 'promo/x/y' } },
        { verification: {} },
      ],
      users: [{ _id: u1, avatarUrl: 'https://res/x.jpg' }, { _id: u2 }],
    });
    expect(out).toEqual([
      { publicId: 'verification/a', resourceType: 'image', type: 'authenticated' },
      { publicId: 'verification/b', resourceType: 'raw', type: 'authenticated' },
      { publicId: 'promo/x/y', resourceType: 'video', type: 'upload' },
      { publicId: `avatars/user_${u1}`, resourceType: 'image', type: 'upload' },
    ]);
  });
  test('nothing in, nothing out', () => {
    expect(collectUploads({})).toEqual([]);
  });
});

describe('confirmation', () => {
  test('a dry run needs no confirmation', () => {
    expect(confirmationProblem({ apply: false }, 'maneyindha')).toBeNull();
  });
  test('--apply needs --confirm equal to the exact database name', () => {
    expect(confirmationProblem({ apply: true, confirm: null }, 'maneyindha')).toMatch(/--confirm/);
    expect(confirmationProblem({ apply: true, confirm: 'Maneyindha' }, 'maneyindha')).toMatch(/exactly/);
    expect(confirmationProblem({ apply: true, confirm: 'other' }, 'maneyindha')).toMatch(/maneyindha/);
    expect(confirmationProblem({ apply: true, confirm: 'maneyindha' }, 'maneyindha')).toBeNull();
  });
});

describe('parseArgs', () => {
  test('safe defaults: dry run, nothing extra', () => {
    expect(parseArgs([])).toEqual({ apply: false, confirm: null, includeCategories: false, includeCoupons: false, purgeUploads: false });
  });
  test('reads every option', () => {
    expect(parseArgs(['--apply', '--confirm=db1', '--include-categories', '--include-coupons', '--purge-uploads']))
      .toEqual({ apply: true, confirm: 'db1', includeCategories: true, includeCoupons: true, purgeUploads: true });
  });
  test('an unknown or misspelled option stops the script instead of being ignored', () => {
    expect(() => parseArgs(['--aply'])).toThrow(/Unknown option/);
    expect(() => parseArgs(['--confirm', 'db1'])).toThrow(/Unknown option/);
  });
});
