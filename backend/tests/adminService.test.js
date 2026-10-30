// Admin statistics, the approval gate and member management (model statics stubbed; no database).
const Business = require('../src/models/Business');
const Notification = require('../src/models/Notification');
const User = require('../src/models/User');
const Order = require('../src/models/Order');
const Review = require('../src/models/Review');
const Coupon = require('../src/models/Coupon');
const RefreshSession = require('../src/models/RefreshSession');
const admin = require('../src/services/admin.service');
const { oid } = require('./helpers');

beforeEach(() => jest.restoreAllMocks());

describe('fillDays', () => {
  const now = new Date('2026-10-28T10:00:00Z');
  test('always returns exactly N consecutive days, oldest first, zero-filled', () => {
    const out = admin.fillDays([{ _id: '2026-10-28', count: 3 }, { _id: '2026-10-26', count: 1 }], 4, now);
    expect(out).toEqual([
      { date: '2026-10-25', count: 0 }, { date: '2026-10-26', count: 1 },
      { date: '2026-10-27', count: 0 }, { date: '2026-10-28', count: 3 },
    ]);
  });
  test('carries several fields', () => {
    const out = admin.fillDays([{ _id: '2026-10-28', count: 2, revenue: 450 }], 2, now, ['count', 'revenue']);
    expect(out).toEqual([{ date: '2026-10-27', count: 0, revenue: 0 }, { date: '2026-10-28', count: 2, revenue: 450 }]);
  });
  test('ignores rows outside the window and tolerates no rows', () => {
    expect(admin.fillDays([{ _id: '2020-01-01', count: 9 }], 2, now).every((p) => p.count === 0)).toBe(true);
    expect(admin.fillDays(undefined, 3, now)).toHaveLength(3);
  });
});

describe('getStats', () => {
  const now = new Date('2026-10-28T10:00:00Z');
  const chain = (rows) => ({ sort: () => ({ limit: () => ({ select: () => ({ populate: async () => rows }) }) }) });
  function stub({ delivered = { _id: 'delivered', n: 4, amount: 2000 } } = {}) {
    const seen = {};
    jest.spyOn(User, 'aggregate').mockImplementation(async (p) => {
      seen.userPipelines = [...(seen.userPipelines || []), p];
      if (p[1]?.$group?._id === '$role') return [{ _id: 'customer', n: 10 }, { _id: 'entrepreneur', n: 3 }, { _id: 'delivery_partner', n: 1 }];
      return [{ _id: '2026-10-27', count: 2 }];
    });
    jest.spyOn(User, 'countDocuments').mockResolvedValueOnce(5).mockResolvedValueOnce(9);
    jest.spyOn(Business, 'aggregate').mockResolvedValue([{ _id: 'approved', n: 2 }, { _id: 'in_review', n: 1 }, { _id: 'pending', n: 4 }, { _id: 'rejected', n: 1 }]);
    jest.spyOn(Business, 'countDocuments').mockResolvedValueOnce(1).mockResolvedValueOnce(2);
    jest.spyOn(Order, 'aggregate').mockImplementation(async (p) => {
      if (p[0]?.$group?._id === '$status') return [{ _id: 'pending', n: 2, amount: 300 }, delivered, { _id: 'cancelled', n: 1, amount: 100 }, { _id: 'rejected', n: 1, amount: 0 }];
      if (p[0]?.$match?.createdAt) return [{ _id: '2026-10-28', count: 2, revenue: 700 }];
      if (p[1]?.$group?._id === '$payment.method') return [{ _id: 'cod', n: 5 }, { _id: 'razorpay', n: 2 }];
      return [{ _id: oid(), orders: 3, revenue: 1500, name: 'Asha Bakes' }];
    });
    jest.spyOn(Order, 'countDocuments').mockResolvedValueOnce(2).mockResolvedValueOnce(1);
    jest.spyOn(Order, 'find').mockReturnValue(chain([
      { _id: oid(), orderNumber: 'MM1', status: 'delivered', amounts: { total: 500 }, payment: { method: 'cod' }, createdAt: now, business: { name: 'Asha Bakes' } },
    ]));
    jest.spyOn(Review, 'aggregate').mockResolvedValue([{ _id: null, count: 7, avg: 4.2857 }]);
    jest.spyOn(Coupon, 'aggregate').mockResolvedValue([{ _id: null, total: 4, active: 4, redeemed: 6 }]);
    return seen;
  }

  test('assembles every number from the database results', async () => {
    stub();
    const s = await admin.getStats(now);
    expect(s.users).toMatchObject({ customers: 10, entrepreneurs: 3, deliveryPartners: 1, total: 14, newLast7Days: 5, newLast30Days: 9 });
    expect(s.users.signupsByDay).toHaveLength(14);
    expect(s.users.signupsByDay.at(-2)).toEqual({ date: '2026-10-27', count: 2 });
    expect(s.shops).toMatchObject({ approved: 2, inReview: 1, pending: 4, rejected: 1, withPromoVideo: 1, openNow: 2 });
    expect(s.shops.topByRevenue).toEqual([expect.objectContaining({ name: 'Asha Bakes', orders: 3, revenue: 1500 })]);
    expect(s.orders).toMatchObject({
      total: 8, today: 2, active: 2, delivered: 4, cancelled: 2, revenueDelivered: 2000, averageOrderValue: 500, needsRefund: 1,
      byPaymentMethod: { cod: 5, razorpay: 2 },
    });
    expect(s.orders.byDay).toHaveLength(14);
    expect(s.orders.byDay.at(-1)).toEqual({ date: '2026-10-28', count: 2, revenue: 700 });
    expect(s.orders.recent[0]).toMatchObject({ orderNumber: 'MM1', total: 500, shop: 'Asha Bakes', method: 'cod' });
    expect(s.reviews).toEqual({ count: 7, average: 4.3 });
    expect(s.coupons).toEqual({ total: 4, active: 4, redeemed: 6 });
  });

  test('an empty database gives zeros, not NaN or a crash', async () => {
    jest.spyOn(User, 'aggregate').mockResolvedValue([]);
    jest.spyOn(User, 'countDocuments').mockResolvedValue(0);
    jest.spyOn(Business, 'aggregate').mockResolvedValue([]);
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(0);
    jest.spyOn(Order, 'aggregate').mockResolvedValue([]);
    jest.spyOn(Order, 'countDocuments').mockResolvedValue(0);
    jest.spyOn(Order, 'find').mockReturnValue(chain([]));
    jest.spyOn(Review, 'aggregate').mockResolvedValue([]);
    jest.spyOn(Coupon, 'aggregate').mockResolvedValue([]);
    const s = await admin.getStats(now);
    expect(s.orders).toMatchObject({ total: 0, delivered: 0, averageOrderValue: 0, revenueDelivered: 0 });
    expect(s.reviews).toEqual({ count: 0, average: 0 });
    expect(JSON.stringify(s)).not.toMatch(/NaN|null/);
  });

  test('administrators are excluded from every people count', async () => {
    const seen = stub();
    await admin.getStats(now);
    for (const p of seen.userPipelines) expect(p[0].$match.role).toEqual({ $nin: ['admin', 'super_admin'] });
    for (const call of User.countDocuments.mock.calls) expect(call[0].role).toEqual({ $nin: ['admin', 'super_admin'] });
  });
});

describe('approval gate', () => {
  const shop = (status, docs) => ({
    _id: oid(), owner: oid(), name: 'Asha Bakes', verification: { status, documents: docs },
    save: jest.fn(async function s() { return this; }),
  });
  const GOOD = [{ type: 'id_proof', publicId: 'verification/a' }, { type: 'business_proof', publicId: 'verification/b' }];
  beforeEach(() => { jest.spyOn(Notification, 'create').mockResolvedValue({}); });
  const review = (b, action, reason) => {
    jest.spyOn(Business, 'findById').mockResolvedValue(b);
    return admin.reviewBusiness(oid(), b._id, { action, reason });
  };

  test('approves a SUBMITTED application with both required documents on file', async () => {
    const b = shop('in_review', GOOD);
    await review(b, 'approve');
    expect(b.verification.status).toBe('approved');
    expect(b.save).toHaveBeenCalled();
    expect(Notification.create).toHaveBeenCalledWith(expect.objectContaining({ title: expect.stringContaining('approved') }));
  });
  test('cannot approve something that was never submitted', async () => {
    const b = shop('pending', GOOD);
    await expect(review(b, 'approve')).rejects.toMatchObject({ statusCode: 422, code: 'NOT_SUBMITTED' });
    expect(b.verification.status).toBe('pending');
    expect(b.save).not.toHaveBeenCalled();
  });
  test.each([
    ['no documents', []],
    ['only ID proof', [GOOD[0]]],
    ['only business proof', [GOOD[1]]],
    ['legacy URL-only documents (no stored file)', [{ type: 'id_proof', url: 'https://x/y.jpg' }, { type: 'business_proof', url: 'https://x/z.jpg' }]],
  ])('cannot approve with %s', async (_n, docs) => {
    const b = shop('in_review', docs);
    await expect(review(b, 'approve')).rejects.toMatchObject({ statusCode: 422, code: 'DOCUMENTS_MISSING' });
    expect(b.verification.status).toBe('in_review');
  });
  test('reject needs a reason; request_info sends it back to pending', async () => {
    await expect(review(shop('in_review', GOOD), 'reject')).rejects.toMatchObject({ statusCode: 422 });
    const b = shop('in_review', GOOD);
    await review(b, 'reject', 'Blurry ID');
    expect(b.verification).toMatchObject({ status: 'rejected', rejectionReason: 'Blurry ID' });
    const c = shop('in_review', GOOD);
    await review(c, 'request_info', 'Please add address proof');
    expect(c.verification.status).toBe('pending');
  });
  test('an already-decided shop cannot be re-reviewed', async () => {
    await expect(review(shop('approved', GOOD), 'reject', 'x')).rejects.toMatchObject({ statusCode: 422 });
    await expect(review(shop('rejected', GOOD), 'approve')).rejects.toMatchObject({ statusCode: 422 });
  });
});

describe('members', () => {
  test('the list never includes admin accounts, and search text is escaped', async () => {
    const find = jest.spyOn(User, 'find').mockReturnValue({ sort: () => ({ skip: () => ({ limit: () => ({ select: async () => [] }) }) }) });
    jest.spyOn(User, 'countDocuments').mockResolvedValue(0);
    await admin.listUsers({ q: '.*(' });
    const filter = find.mock.calls[0][0];
    expect(filter.role).toEqual({ $nin: ['admin', 'super_admin'] });
    expect(filter.$or[0].name.test('anything at all')).toBe(false); // ".*(" was escaped, not treated as a pattern
    expect(filter.$or[0].name.test('a.*(b')).toBe(true);
  });
  test('suspending signs the member out everywhere; restoring does not', async () => {
    const u = { _id: oid(), role: 'customer', email: 'a@b.c', isActive: true, save: jest.fn() };
    jest.spyOn(User, 'findById').mockResolvedValue(u);
    jest.spyOn(Business, 'updateMany').mockResolvedValue({});
    jest.spyOn(Notification, 'create').mockResolvedValue({});
    jest.spyOn(require('../src/services/email.service'), 'sendNoticeEmail').mockResolvedValue({ sent: true });
    const del = jest.spyOn(RefreshSession, 'deleteMany').mockResolvedValue({});
    expect(await admin.setUserActive(u._id, false, { reason: 'Account misuse' })).toMatchObject({ id: u._id, isActive: false });
    expect(del).toHaveBeenCalledWith({ user: u._id });
    del.mockClear();
    await admin.setUserActive(u._id, true);
    expect(u.isActive).toBe(true);
    expect(del).not.toHaveBeenCalled();
  });
  test('the administrator account cannot be changed; unknown users are 404', async () => {
    jest.spyOn(User, 'findById').mockResolvedValueOnce({ _id: oid(), role: 'admin' });
    await expect(admin.setUserActive(oid(), false)).rejects.toMatchObject({ statusCode: 403 });
    jest.spyOn(User, 'findById').mockResolvedValueOnce(null);
    await expect(admin.setUserActive(oid(), false)).rejects.toMatchObject({ statusCode: 404 });
  });
});
