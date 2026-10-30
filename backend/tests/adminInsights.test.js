// Admin insight views: owners, shops, products, badges, growth (models stubbed; no database, no network).
const request = require('supertest');
const mongoose = require('mongoose');
const Business = require('../src/models/Business');
const Product = require('../src/models/Product');
const User = require('../src/models/User');
const Order = require('../src/models/Order');
const rewards = require('../src/services/rewards.service');
const ins = require('../src/services/adminInsights.service');
const { oid, bearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');

// A Mongoose-like chain that resolves to `result` wherever it ends.
const chain = (result) => {
  const q = { sort: () => q, skip: () => q, limit: () => q, select: () => q, populate: () => q, lean: () => q, then: (res, rej) => Promise.resolve(result).then(res, rej) };
  return q;
};
beforeEach(() => jest.restoreAllMocks());

describe('summarizeOwner: the same rules the owner sees', () => {
  const shop = (o = {}) => ({ _id: oid(), isActive: true, rating: { avg: 0, count: 0 }, ...o });
  test('badge tier comes from delivered orders of ACTIVE shops; totals cover every shop', () => {
    const a = shop(); const b = shop({ isActive: false });
    const r = ins._summarizeOwner([a, b], [{ _id: a._id, orders: 12, revenue: 3000 }, { _id: b._id, orders: 40, revenue: 9000 }]);
    expect(r).toMatchObject({ shops: 2, activeShops: 1, delivered: 52, revenue: 12000, badge: { id: 'rising' } }); // 12 -> Rising, not 52 -> Trusted
  });
  test('tiers at 0, 1, 10, 30 and 100 delivered orders', () => {
    const s = shop();
    const tier = (n) => ins._summarizeOwner([s], n ? [{ _id: s._id, orders: n, revenue: 0 }] : []).badge.id;
    expect([0, 1, 9, 10, 29, 30, 99, 100].map(tier)).toEqual(['new_maker', 'first_sale', 'first_sale', 'rising', 'rising', 'trusted', 'trusted', 'star']);
  });
  test('Highly Rated needs 4.5 from 5+ reviews (weighted across shops); On Camera needs an APPROVED video on an active shop', () => {
    const good = [shop({ rating: { avg: 5, count: 3 } }), shop({ rating: { avg: 4, count: 2 } })]; // (15+8)/5 = 4.6
    expect(ins._summarizeOwner(good, []).achievements.wellRated).toBe(true);
    expect(ins._summarizeOwner([shop({ rating: { avg: 5, count: 4 } })], []).achievements.wellRated).toBe(false);
    expect(ins._summarizeOwner([shop({ rating: { avg: 4.4, count: 50 } })], []).achievements.wellRated).toBe(false);
    expect(ins._summarizeOwner([shop({ promoVideo: { review: { status: 'pending' } } })], []).achievements.onVideo).toBe(false);
    expect(ins._summarizeOwner([shop({ promoVideo: { review: { status: 'approved' } } })], []).achievements.onVideo).toBe(true);
    expect(ins._summarizeOwner([shop({ isActive: false, promoVideo: { review: { status: 'approved' } } })], []).achievements.onVideo).toBe(false);
  });
});

describe('months', () => {
  test('fillMonths returns n consecutive months, oldest first, zero-filled, across a year boundary', () => {
    const out = ins.fillMonths([{ _id: '2026-01', count: 4, revenue: 90 }, { _id: '2025-11', count: 1, revenue: 5 }], 4, new Date('2026-02-10T00:00:00Z'), ['count', 'revenue']);
    expect(out).toEqual([
      { month: '2025-11', count: 1, revenue: 5 }, { month: '2025-12', count: 0, revenue: 0 },
      { month: '2026-01', count: 4, revenue: 90 }, { month: '2026-02', count: 0, revenue: 0 },
    ]);
  });
  test('pctChange is null with no previous value, otherwise a one-decimal percentage (negative allowed)', () => {
    expect(ins.pctChange(5, 0)).toBeNull();
    expect(ins.pctChange(15, 10)).toBe(50);
    expect(ins.pctChange(7, 9)).toBe(-22.2);
  });
});

describe('owners list', () => {
  test('lists only people who own a shop, never admins, escapes the search, and attaches each owner summary', async () => {
    const ownerA = oid(); const shopA = oid();
    jest.spyOn(Business, 'distinct').mockResolvedValue([ownerA]);
    const find = jest.spyOn(User, 'find').mockReturnValue(chain([{ _id: ownerA, name: 'Asha', email: 'a@x.in', isActive: true, createdAt: new Date() }]));
    jest.spyOn(User, 'countDocuments').mockResolvedValue(1);
    jest.spyOn(Business, 'find').mockReturnValue(chain([{ _id: shopA, owner: ownerA, isActive: true, rating: { avg: 5, count: 6 } }]));
    jest.spyOn(Order, 'aggregate').mockResolvedValue([{ _id: shopA, orders: 31, revenue: 12000 }]);
    const r = await ins.owners({ q: '.*(' });
    const filter = find.mock.calls[0][0];
    expect(filter.role).toEqual({ $nin: ['admin', 'super_admin'] });
    expect(filter._id).toEqual({ $in: [ownerA] });
    expect(filter.$or[0].name.test('anything')).toBe(false); // the search text was escaped, not run as a pattern
    expect(r.meta.total).toBe(1);
    expect(r.items[0]).toMatchObject({ name: 'Asha', delivered: 31, revenue: 12000, badge: { id: 'trusted' }, achievements: { wellRated: true } });
  });
});

describe('shops list', () => {
  test('status filters: suspended means hidden, the others use the verification status; deleted shops never appear', async () => {
    const find = jest.spyOn(Business, 'find').mockReturnValue(chain([]));
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(0);
    jest.spyOn(Order, 'aggregate').mockResolvedValue([]);
    await ins.shops({ status: 'suspended' });
    expect(find.mock.calls[0][0]).toEqual({ deletedAt: null, isActive: false });
    await ins.shops({ status: 'in_review', q: 'bak' });
    expect(find.mock.calls[1][0]).toMatchObject({ deletedAt: null, 'verification.status': 'in_review' });
  });
  test('each row carries owner, suspension reason, products, delivered orders and revenue', async () => {
    const sid = oid(); const oidv = oid();
    jest.spyOn(Business, 'find').mockReturnValue(chain([{
      _id: sid, name: 'Asha Bakes', isActive: false, verification: { status: 'approved' },
      suspension: { reason: 'Reported', at: new Date(), byOwner: false }, owner: { _id: oidv, name: 'Asha', email: 'a@x.in' },
      bannerUrl: 'https://res.cloudinary.com/demo/image/upload/shop.jpg',
    }]));
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(1);
    jest.spyOn(Order, 'aggregate').mockResolvedValue([{ _id: sid, orders: 3, revenue: 450 }]);
    jest.spyOn(Product, 'aggregate').mockResolvedValue([{ _id: sid, n: 7 }]);
    const { items } = await ins.shops({});
    expect(items[0]).toMatchObject({
      name: 'Asha Bakes', isActive: false, products: 7, delivered: 3, revenue: 450, coverUrl: 'https://res.cloudinary.com/demo/image/upload/shop.jpg',
      owner: { name: 'Asha' }, suspension: { reason: 'Reported', byOwner: false },
    });
  });
});

describe('products list', () => {
  test('a malformed shop id is refused; rows report low stock and only https images', async () => {
    await expect(ins.products({ business: 'nope' })).rejects.toMatchObject({ statusCode: 422 });
    jest.spyOn(Product, 'find').mockReturnValue(chain([
      { _id: oid(), name: 'Jam', price: 120, stock: 2, lowStockThreshold: 5, images: ['http://x/a.jpg', 'https://x/b.jpg'], business: { _id: oid(), name: 'Asha Bakes' } },
      { _id: oid(), name: 'Pickle', price: 90, stock: 40, images: [], business: null },
    ]));
    jest.spyOn(Product, 'countDocuments').mockResolvedValue(2);
    const { items } = await ins.products({});
    expect(items[0]).toMatchObject({ lowStock: true, imageUrl: 'https://x/b.jpg', shop: { name: 'Asha Bakes' } });
    expect(items[1]).toMatchObject({ lowStock: false, imageUrl: undefined, shop: null });
  });
});

describe('badges overview', () => {
  test('counts owners per tier and achievement, and ranks the leaders by delivered orders', async () => {
    const [o1, o2, o3] = [oid(), oid(), oid()]; const [s1, s2, s3] = [oid(), oid(), oid()];
    jest.spyOn(Business, 'distinct').mockResolvedValue([o1, o2, o3]);
    jest.spyOn(User, 'find').mockReturnValue(chain([{ _id: o1, name: 'A' }, { _id: o2, name: 'B' }, { _id: o3, name: 'C' }]));
    jest.spyOn(Business, 'find').mockReturnValue(chain([
      { _id: s1, owner: o1, isActive: true, promoVideo: { review: { status: 'approved' } } },
      { _id: s2, owner: o2, isActive: true }, { _id: s3, owner: o3, isActive: true },
    ]));
    jest.spyOn(Order, 'aggregate').mockResolvedValue([{ _id: s1, orders: 120, revenue: 1 }, { _id: s2, orders: 12, revenue: 1 }]);
    const r = await ins.badges();
    expect(r.totalOwners).toBe(3);
    expect(Object.fromEntries(r.tiers.map((t) => [t.id, t.owners]))).toEqual({ new_maker: 1, first_sale: 0, rising: 1, trusted: 0, star: 1 });
    expect(r.achievements.find((a) => a.id === 'on_video').owners).toBe(1);
    expect(r.leaders.map((l) => l.name)).toEqual(['A', 'B', 'C']);
    expect(r.tiers.map((t) => t.id)).toEqual(rewards.SELLER_TIERS.map((t) => t.id)); // same tiers the owners see
  });
});

describe('growth', () => {
  test('monthly series, this month, month-on-month change and totals', async () => {
    const now = new Date('2026-10-15T00:00:00Z');
    jest.spyOn(User, 'aggregate')
      .mockResolvedValueOnce([{ _id: '2026-09', count: 10 }, { _id: '2026-10', count: 15 }]) // customers
      .mockResolvedValueOnce([{ _id: '2026-10', count: 2 }]) // entrepreneurs
      .mockResolvedValueOnce([{ _id: 'customer', n: 40 }, { _id: 'entrepreneur', n: 6 }]);
    jest.spyOn(Business, 'aggregate').mockResolvedValue([{ _id: '2026-10', count: 1 }]);
    jest.spyOn(Order, 'aggregate')
      .mockResolvedValueOnce([{ _id: '2026-09', count: 4, revenue: 400 }, { _id: '2026-10', count: 6, revenue: 900 }])
      .mockResolvedValueOnce([{ _id: 'delivered', n: 8, amount: 1500 }, { _id: 'pending', n: 2, amount: 100 }]);
    jest.spyOn(Business, 'countDocuments').mockResolvedValueOnce(9).mockResolvedValueOnce(7);
    jest.spyOn(Product, 'countDocuments').mockResolvedValue(33);
    const g = await ins.growth({ months: 4 }, now);
    expect(g.series.map((s) => s.month)).toEqual(['2026-07', '2026-08', '2026-09', '2026-10']);
    expect(g.thisMonth).toMatchObject({ month: '2026-10', customers: 15, entrepreneurs: 2, shops: 1, orders: 6, revenue: 900 });
    expect(g.change).toMatchObject({ customers: 50, orders: 50, revenue: 125, entrepreneurs: null, shops: null });
    expect(g.totals).toEqual({ customers: 40, entrepreneurs: 6, shops: 9, approvedShops: 7, products: 33, orders: 10, deliveredOrders: 8, revenue: 1500 });
  });
  test('months is clamped to 3..12', async () => {
    for (const m of [1, 99]) {
      jest.spyOn(User, 'aggregate').mockResolvedValue([]);
      jest.spyOn(Business, 'aggregate').mockResolvedValue([]);
      jest.spyOn(Order, 'aggregate').mockResolvedValue([]);
      jest.spyOn(Business, 'countDocuments').mockResolvedValue(0);
      jest.spyOn(Product, 'countDocuments').mockResolvedValue(0);
      expect((await ins.growth({ months: m })).series).toHaveLength(m === 1 ? 3 : 12);
    }
  });
});

describe('detail', () => {
  test('a malformed or unknown owner is 404', async () => {
    await expect(ins.ownerDetail('nope')).rejects.toMatchObject({ statusCode: 404 });
    jest.spyOn(User, 'findOne').mockReturnValue(chain(null));
    await expect(ins.ownerDetail(String(oid()))).rejects.toMatchObject({ statusCode: 404 });
  });
  test('an owner with shops gets summary, the owner-facing badges, per-shop numbers and six months of growth', async () => {
    const owner = oid(); const shopId = oid();
    jest.spyOn(User, 'findOne').mockReturnValue(chain({ _id: owner, name: 'Asha', email: 'a@x.in', isActive: true, suspension: undefined }));
    jest.spyOn(Business, 'find').mockReturnValue(chain([{ _id: shopId, name: 'Asha Bakes', isActive: true, verification: { status: 'approved' }, rating: { avg: 4.8, count: 9 } }]));
    jest.spyOn(Order, 'aggregate')
      .mockResolvedValueOnce([{ _id: shopId, orders: 11, revenue: 2200 }]) // delivered by shop
      .mockResolvedValueOnce([{ _id: '2026-10', count: 5, revenue: 900 }]); // monthly
    jest.spyOn(Product, 'aggregate').mockResolvedValue([{ _id: shopId, n: 4 }]);
    const owned = { badge: { id: 'rising' }, badges: [], achievements: [] };
    jest.spyOn(rewards, 'getSellerBadges').mockResolvedValue(owned);
    const d = await ins.ownerDetail(String(owner), new Date('2026-10-20T00:00:00Z'));
    expect(d.badges).toBe(owned);
    expect(d.summary).toMatchObject({ delivered: 11, revenue: 2200, badge: { id: 'rising' }, achievements: { wellRated: true } });
    expect(d.shops[0]).toMatchObject({ name: 'Asha Bakes', products: 4, delivered: 11, revenue: 2200 });
    expect(d.monthly).toHaveLength(6);
    expect(d.monthly[5]).toEqual({ month: '2026-10', count: 5, revenue: 900 });
  });
});

describe('only the administrator can open these', () => {
  test.each(['/admin/owners', `/admin/owners/${oid()}`, '/admin/shops', '/admin/products', '/admin/badges', '/admin/growth'])('%s', async (path) => {
    for (const role of ['customer', 'entrepreneur']) {
      expect((await request(app).get(`/api/v1${path}`).set(bearer(role))).status).toBe(403);
    }
    expect((await request(app).get(`/api/v1${path}`)).status).toBe(401);
  });
});
