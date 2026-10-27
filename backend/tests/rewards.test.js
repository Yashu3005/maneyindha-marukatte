// Loyalty badges and reward coupons: tiers, status per customer, and eligibility enforced at checkout.
const request = require('supertest');
const mongoose = require('mongoose');
const Coupon = require('../src/models/Coupon');
const Order = require('../src/models/Order');
const rewards = require('../src/services/rewards.service');
const cartService = require('../src/services/cart.service');
const { oid, bearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');

beforeEach(() => jest.restoreAllMocks());

describe('badge tiers (from DELIVERED orders)', () => {
  test.each([
    [0, 'new'], [1, 'explorer'], [2, 'explorer'], [3, 'regular'], [5, 'regular'],
    [6, 'loyal'], [11, 'loyal'], [12, 'champion'], [500, 'champion'],
  ])('%i delivered orders -> %s', (n, id) => {
    expect(rewards.tierFor(n).id).toBe(id);
  });
  test.each([
    [5, 5, 'Weekly regular'], [4, 4, 'Weekly regular'], [3, 3, 'Ordering often this month'], [2, 9, 'Ordering often this month'],
    [1, 1, 'Ordered this month'], [0, 2, 'Ordered in the last 3 months'], [0, 0, null],
  ])('frequency last30=%i last90=%i -> %s', (a, b, label) => {
    expect(rewards.frequencyLabel(a, b)).toBe(label);
  });
});

describe('reward coupons', () => {
  test('are created once, with $setOnInsert so existing edits are never overwritten', async () => {
    const upd = jest.spyOn(Coupon, 'updateOne').mockResolvedValue({});
    await rewards.ensureRewardCoupons();
    expect(upd).toHaveBeenCalledTimes(rewards.PROGRAMME.length);
    for (const [filter, update, opts] of upd.mock.calls) {
      expect(filter).toEqual({ code: expect.any(String) });
      expect(opts).toEqual({ upsert: true });
      expect(Object.keys(update)).toEqual(['$setOnInsert']);
      expect(update.$setOnInsert).toMatchObject({ isReward: true, usageLimitPerUser: 1, isActive: true });
      expect(update.$setOnInsert.audience).toBeUndefined();
    }
  });
  test('isRewardCode is case-insensitive and only knows the programme', () => {
    expect(rewards.isRewardCode('welcome10')).toBe(true);
    expect(rewards.isRewardCode('CHAMPION100')).toBe(true);
    expect(rewards.isRewardCode('FREEMONEY')).toBe(false);
    expect(rewards.isRewardCode(undefined)).toBe(false);
  });
});

describe('getRewards', () => {
  const docs = () => rewards.PROGRAMME.map(({ audience: _a, ...p }) => ({ ...p, usageLimitPerUser: 1, isActive: true }));
  function setup({ delivered = 0, last30 = 0, last90 = 0, spent = 0, used = [] } = {}) {
    jest.spyOn(Coupon, 'updateOne').mockResolvedValue({});
    jest.spyOn(Coupon, 'find').mockResolvedValue(docs());
    jest.spyOn(Order, 'aggregate').mockImplementation(async (pipeline) => {
      if (pipeline[0].$match.status === 'delivered') {
        return delivered ? [{ _id: null, delivered, spent, last30, last90, firstOrderAt: new Date('2026-01-01'), lastOrderAt: new Date('2026-10-01') }] : [];
      }
      return used.map((code) => ({ _id: code, n: 1 }));
    });
  }
  const statusOf = (r, code) => r.coupons.find((c) => c.code === code)?.status;

  test('a brand-new customer: New Member, welcome offer available, loyalty rewards locked with a hint', async () => {
    setup();
    const r = await rewards.getRewards(oid());
    expect(r.badge).toMatchObject({ id: 'new', label: 'New Member' });
    expect(r.next).toMatchObject({ id: 'explorer', ordersToGo: 1 });
    expect(statusOf(r, 'WELCOME10')).toBe('available');
    expect(statusOf(r, 'REGULAR5')).toBe('locked');
    expect(r.coupons.find((c) => c.code === 'REGULAR5').unlockHint).toBe('Unlocks after 3 more delivered orders');
    expect(r.coupons.find((c) => c.code === 'CHAMPION100').unlockHint).toBe('Unlocks after 12 more delivered orders');
    expect(r.stats).toMatchObject({ deliveredOrders: 0, frequency: null });
    expect(r.badges.map((b) => b.earned)).toEqual([true, false, false, false, false]);
  });
  test('after the first delivery the welcome offer disappears; Explorer', async () => {
    setup({ delivered: 1, last30: 1, last90: 1, spent: 250 });
    const r = await rewards.getRewards(oid());
    expect(r.badge.id).toBe('explorer');
    expect(statusOf(r, 'WELCOME10')).toBeUndefined();
    expect(r.coupons.find((c) => c.code === 'REGULAR5').unlockHint).toBe('Unlocks after 2 more delivered orders');
    expect(r.stats).toMatchObject({ deliveredOrders: 1, totalSpent: 250, frequency: 'Ordered this month' });
  });
  test('a Regular: REGULAR5 available, higher tiers locked, a used reward is marked used', async () => {
    setup({ delivered: 4, last30: 4, last90: 4, used: ['REGULAR5'] });
    const r = await rewards.getRewards(oid());
    expect(r.badge.id).toBe('regular');
    expect(statusOf(r, 'REGULAR5')).toBe('used');
    expect(statusOf(r, 'LOYAL10')).toBe('locked');
    expect(r.next).toMatchObject({ id: 'loyal', ordersToGo: 2 });
    expect(r.stats.frequency).toBe('Weekly regular');
  });
  test('a Champion has everything unlocked and no next badge', async () => {
    setup({ delivered: 12 });
    const r = await rewards.getRewards(oid());
    expect(r.badge.id).toBe('champion');
    expect(r.next).toBeNull();
    for (const c of ['REGULAR5', 'LOYAL10', 'CHAMPION100']) expect(statusOf(r, c)).toBe('available');
  });
  test('a used welcome offer is shown as used (so the customer knows they had it)', async () => {
    setup({ used: ['WELCOME10'] });
    expect(statusOf(await rewards.getRewards(oid()), 'WELCOME10')).toBe('used');
  });
  test('GET /rewards/me needs sign-in and is not cached', async () => {
    expect((await request(app).get('/api/v1/rewards/me')).status).toBe(401);
    setup();
    const res = await request(app).get('/api/v1/rewards/me').set(bearer('customer'));
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.body.data.badge.id).toBe('new');
  });
});

describe('checkout enforces eligibility (a locked code cannot be typed in)', () => {
  const coupon = (def) => { const c = { ...rewards.PROGRAMME.find((p) => p.code === def) }; delete c.audience; return { ...c, usageLimitPerUser: 1, usedCount: 0 }; };
  function ctx(code, delivered, usedBefore = 0) {
    jest.spyOn(Coupon, 'findOne').mockResolvedValue(coupon(code));
    jest.spyOn(Order, 'countDocuments').mockImplementation(async (q) => (q.status === 'delivered' ? delivered : usedBefore));
  }
  const check = (code, subtotal = 1000) => cartService.validateCoupon(code, { businessId: oid(), subtotal, customerId: oid() });

  test('WELCOME10: ok for a customer with no delivered orders, refused afterwards', async () => {
    ctx('WELCOME10', 0);
    await expect(check('WELCOME10')).resolves.toMatchObject({ code: 'WELCOME10' });
    ctx('WELCOME10', 1);
    await expect(check('WELCOME10')).rejects.toMatchObject({ statusCode: 422, code: 'COUPON_NOT_ELIGIBLE', message: 'This offer is for new customers only' });
  });
  test.each([['REGULAR5', 3], ['LOYAL10', 6], ['CHAMPION100', 12]])('%s unlocks at exactly %i delivered orders', async (code, min) => {
    ctx(code, min - 1);
    await expect(check(code)).rejects.toMatchObject({ code: 'COUPON_NOT_ELIGIBLE', message: 'Unlocks after 1 more delivered order' });
    ctx(code, min);
    await expect(check(code)).resolves.toMatchObject({ code });
  });
  test('each reward can be used once per customer', async () => {
    ctx('REGULAR5', 5, 1);
    await expect(check('REGULAR5')).rejects.toMatchObject({ message: 'You have already used this coupon' });
  });
  test('minimum order amount still applies', async () => {
    ctx('CHAMPION100', 20);
    await expect(check('CHAMPION100', 299)).rejects.toMatchObject({ message: 'Minimum order amount is 300' });
  });
  test('a reward code typed before it exists in the database is created on demand; unknown codes are not', async () => {
    const find = jest.spyOn(Coupon, 'findOne').mockResolvedValueOnce(null).mockResolvedValueOnce(coupon('WELCOME10'));
    const upd = jest.spyOn(Coupon, 'updateOne').mockResolvedValue({});
    jest.spyOn(Order, 'countDocuments').mockResolvedValue(0);
    await expect(check('welcome10')).resolves.toMatchObject({ code: 'WELCOME10' });
    expect(upd).toHaveBeenCalledTimes(rewards.PROGRAMME.length);
    expect(find).toHaveBeenCalledTimes(2);
    upd.mockClear();
    jest.spyOn(Coupon, 'findOne').mockResolvedValue(null);
    await expect(check('FREEMONEY')).rejects.toMatchObject({ message: 'Invalid coupon' });
    expect(upd).not.toHaveBeenCalled();
  });
  test('ordinary (non-reward) coupons are unaffected by delivered-order counts', async () => {
    jest.spyOn(Coupon, 'findOne').mockResolvedValue({ code: 'DIWALI', type: 'flat', value: 50, minOrderAmount: 0, usedCount: 0, usageLimitPerUser: 1 });
    const count = jest.spyOn(Order, 'countDocuments').mockResolvedValue(0);
    await expect(check('DIWALI')).resolves.toMatchObject({ code: 'DIWALI' });
    expect(count.mock.calls.every(([q]) => q.status !== 'delivered')).toBe(true);
  });
});
