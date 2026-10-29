// Verified-purchase ratings, the rating summary, and shop filters / nearest sorting.
process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const Business = require('../src/models/Business');
const Category = require('../src/models/Category');
const Product = require('../src/models/Product');
const Order = require('../src/models/Order');
const Review = require('../src/models/Review');
const reviewService = require('../src/services/review.service');
const { oid, bearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';

beforeEach(() => jest.restoreAllMocks());

describe('ratings come only from real buyers', () => {
  const productId = oid(); const shopId = oid(); const customer = String(oid()); const orderId = oid();
  function setup({ order = { _id: orderId }, own = false } = {}) {
    jest.spyOn(Product, 'findOne').mockResolvedValue({ _id: productId, business: shopId });
    jest.spyOn(Business, 'exists').mockResolvedValue(own ? { _id: shopId } : null);
    const findOrder = jest.spyOn(Order, 'findOne').mockResolvedValue(order);
    const create = jest.spyOn(Review, 'create').mockImplementation(async (d) => ({ ...d, _id: oid() }));
    jest.spyOn(Review, 'aggregate').mockResolvedValue([]);
    jest.spyOn(Product, 'findByIdAndUpdate').mockResolvedValue({});
    jest.spyOn(Business, 'findByIdAndUpdate').mockResolvedValue({});
    return { findOrder, create };
  }
  const post = (body, role = 'customer') => request(app).post(`${api}/reviews`).set(bearer(role, customer)).send(body);
  const body = { productId: String(productId), orderId: String(orderId), rating: 5 };

  test('a rating without an order is refused (HTTP: validation; service: ORDER_REQUIRED)', async () => {
    setup();
    expect((await post({ productId: String(productId), rating: 5 })).status).toBe(422);
    await expect(reviewService.createReview(customer, { productId, rating: 5 })).rejects.toMatchObject({ statusCode: 422, code: 'ORDER_REQUIRED' });
  });
  test('only a DELIVERED order of this customer that contains the product counts', async () => {
    const { findOrder, create } = setup();
    const res = await post(body);
    expect(res.status).toBe(201);
    expect(findOrder).toHaveBeenCalledWith({ _id: String(orderId), customer, status: 'delivered', 'items.product': String(productId) });
    expect(create.mock.calls[0][0]).toMatchObject({ isVerifiedPurchase: true, customer, business: shopId, rating: 5 });
  });
  test('no matching delivered order -> 422 and nothing is stored', async () => {
    const { create } = setup({ order: null });
    expect((await post(body)).status).toBe(422);
    expect(create).not.toHaveBeenCalled();
  });
  test('you cannot rate your own shop\'s products', async () => {
    const { create } = setup({ own: true });
    expect((await post(body)).status).toBe(403);
    expect(create).not.toHaveBeenCalled();
  });
  test('rating stays 1–5 whole numbers', async () => {
    setup();
    for (const rating of [0, 6, 4.5, '5x']) expect((await post({ ...body, rating })).status).toBe(422);
  });
});

describe('toRate: what I can still rate', () => {
  test('lists delivered-order items that have no review yet, and drops finished orders', async () => {
    const o1 = { _id: oid(), orderNumber: 'MM1', updatedAt: new Date(), business: { _id: oid(), name: 'Asha' }, items: [{ product: oid(), name: 'Cake' }, { product: oid(), name: 'Bread' }] };
    const o2 = { _id: oid(), orderNumber: 'MM2', updatedAt: new Date(), business: { _id: oid(), name: 'Kala' }, items: [{ product: oid(), name: 'Bag' }] };
    jest.spyOn(Order, 'find').mockReturnValue({ sort: () => ({ limit: () => ({ populate: async () => [o1, o2] }) }) });
    jest.spyOn(Review, 'find').mockReturnValue({ select: async () => [{ order: o1._id, product: o1.items[0].product }, { order: o2._id, product: o2.items[0].product }] });
    const out = await reviewService.toRate(oid());
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ orderNumber: 'MM1', business: { name: 'Asha' } });
    expect(out[0].items.map((i) => i.name)).toEqual(['Bread']);
  });
  test('no delivered orders -> empty, without touching reviews', async () => {
    jest.spyOn(Order, 'find').mockReturnValue({ sort: () => ({ limit: () => ({ populate: async () => [] }) }) });
    const rf = jest.spyOn(Review, 'find');
    expect(await reviewService.toRate(oid())).toEqual([]);
    expect(rf).not.toHaveBeenCalled();
  });
  test('GET /reviews/to-rate needs sign-in', async () => {
    expect((await request(app).get(`${api}/reviews/to-rate`)).status).toBe(401);
  });
});

describe('rating summary', () => {
  test('average, count and star spread are computed from the reviews', async () => {
    jest.spyOn(Review, 'aggregate').mockResolvedValue([{ _id: 5, n: 3 }, { _id: 4, n: 1 }, { _id: 1, n: 1 }]);
    expect(await reviewService.businessSummary(oid())).toEqual({ average: 4.0, count: 5, distribution: { 1: 1, 2: 0, 3: 0, 4: 1, 5: 3 } });
  });
  test('no reviews -> zeros (no NaN)', async () => {
    jest.spyOn(Review, 'aggregate').mockResolvedValue([]);
    expect(await reviewService.businessSummary(oid())).toEqual({ average: 0, count: 0, distribution: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 } });
  });
  test('HTTP: public for approved shops, 404 for unapproved or malformed ids', async () => {
    const id = oid();
    jest.spyOn(Business, 'findOne').mockReturnValue({ select: async () => ({ _id: id }) });
    jest.spyOn(Review, 'aggregate').mockResolvedValue([{ _id: 3, n: 2 }]);
    const ok = await request(app).get(`${api}/businesses/${id}/rating-summary`);
    expect(ok.status).toBe(200);
    expect(ok.body.data).toMatchObject({ average: 3, count: 2 });
    expect(Business.findOne).toHaveBeenCalledWith(expect.objectContaining({ 'verification.status': 'approved', isActive: true }));
    Business.findOne.mockReturnValue({ select: async () => null });
    expect((await request(app).get(`${api}/businesses/${id}/rating-summary`)).status).toBe(404);
    expect((await request(app).get(`${api}/businesses/not-an-id/rating-summary`)).status).toBe(404);
  });
});

describe('shop filters', () => {
  const found = [];
  function listSpy() {
    const q = { select: () => q, sort: jest.fn(() => q), skip: () => q, limit: () => q, populate: async () => found };
    const find = jest.spyOn(Business, 'find').mockReturnValue(q);
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(0);
    return { find, q };
  }

  test('defaults: approved + active shops, best rated first', async () => {
    const { find, q } = listSpy();
    expect((await request(app).get(`${api}/businesses`)).status).toBe(200);
    expect(find.mock.calls[0][0]).toEqual({ 'verification.status': 'approved', isActive: true });
    expect(q.sort).toHaveBeenCalledWith('-rating.avg');
  });
  test('minRating, openNow, hasVideo, text, sort', async () => {
    const { find, q } = listSpy();
    await request(app).get(`${api}/businesses?minRating=4&openNow=true&hasVideo=true&q=asha.*&sort=newest`);
    const f = find.mock.calls[0][0];
    expect(f['rating.avg']).toEqual({ $gte: 4 });
    expect(f['rating.count']).toEqual({ $gte: 1 });
    expect(f.isOpen).toBe(true);
    expect(f['promoVideo.review.status']).toBe('approved');
    expect(f.name.test('Asha Bakes')).toBe(false); // the ".*" is literal text, not a pattern
    expect(f.name.test('xx asha.* yy')).toBe(true);
    expect(q.sort).toHaveBeenCalledWith('-createdAt');
  });
  test('minRating is capped at 5 and junk is ignored; unknown sort falls back', async () => {
    const { find, q } = listSpy();
    await request(app).get(`${api}/businesses?minRating=99&sort=__proto__`);
    expect(find.mock.calls[0][0]['rating.avg']).toEqual({ $gte: 5 });
    expect(q.sort).toHaveBeenCalledWith('-rating.avg');
    find.mockClear();
    await request(app).get(`${api}/businesses?minRating=abc&openNow=false&hasVideo=no`);
    const f = find.mock.calls[0][0];
    expect(f['rating.avg']).toBeUndefined(); expect(f.isOpen).toBeUndefined(); expect(f['promoVideo.review.status']).toBeUndefined();
  });
  test('category by id or by name; an unknown name matches no shops', async () => {
    const { find } = listSpy();
    const id = String(oid());
    await request(app).get(`${api}/businesses?category=${id}`);
    expect(String(find.mock.calls[0][0].category)).toBe(id);
    const cat = oid();
    const fc = jest.spyOn(Category, 'findOne').mockReturnValue({ select: async () => ({ _id: cat }) });
    await request(app).get(`${api}/businesses?category=baking`);
    expect(fc.mock.calls[0][0].name.test('Baking')).toBe(true);
    expect(fc.mock.calls[0][0].name.test('Baking supplies')).toBe(false); // exact name only
    expect(find.mock.calls[1][0].category).toEqual(cat);
    fc.mockReturnValue({ select: async () => null });
    await request(app).get(`${api}/businesses?category=nonexistent`);
    expect(find.mock.calls[2][0].category).toEqual({ $in: [] });
  });

  describe('near me', () => {
    const near = '/businesses/nearby?lat=12.97&lng=77.59';
    test('default: nearest first via $near, with the radius in metres', async () => {
      const { find, q } = listSpy();
      await request(app).get(`${api}${near}&radiusKm=5`);
      const f = find.mock.calls[0][0];
      expect(f.publicLocation.$near).toEqual({ $geometry: { type: 'Point', coordinates: [77.59, 12.97] }, $maxDistance: 5000 });
      expect(q.sort).not.toHaveBeenCalled();
    });
    test('sort=rating keeps the radius but orders by rating ($geoWithin)', async () => {
      const { find, q } = listSpy();
      await request(app).get(`${api}${near}&radiusKm=5&sort=rating&minRating=4`);
      const f = find.mock.calls[0][0];
      expect(f.publicLocation.$near).toBeUndefined();
      expect(f.publicLocation.$geoWithin.$centerSphere[0]).toEqual([77.59, 12.97]);
      expect(f.publicLocation.$geoWithin.$centerSphere[1]).toBeCloseTo(5 / 6378.1, 8);
      expect(f['rating.avg']).toEqual({ $gte: 4 });
      expect(q.sort).toHaveBeenCalledWith('-rating.avg');
    });
    test('distance is still reported and the exact location is never returned', async () => {
      const shop = { toObject: () => ({ name: 'Asha', location: { coordinates: [1, 1] }, publicLocation: { type: 'Point', coordinates: [77.6, 12.98] }, locationSource: 'device' }) };
      found.length = 0; found.push(shop);
      listSpy();
      const res = await request(app).get(`${api}${near}`);
      found.length = 0;
      const b = res.body.data[0];
      expect(b.distanceKm).toBeGreaterThan(0);
      expect(b.location.coordinates).toEqual([77.6, 12.98]);
      expect(b.locationSource).toBeUndefined();
      expect(b.publicLocation).toBeUndefined();
    });
    test('bad coordinates are still rejected', async () => {
      listSpy();
      expect((await request(app).get(`${api}/businesses/nearby?lat=999&lng=77`)).status).toBe(422);
      expect((await request(app).get(`${api}/businesses/nearby`)).status).toBe(422);
    });
  });
});
