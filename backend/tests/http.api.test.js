// HTTP-level tests against the real Express app (routing, auth, RBAC, validation,
// error handling). No database is attached: mongoose is told to fail fast, and every
// assertion here is on behaviour that must happen BEFORE any DB access.
const { bearer, tokenFor, oid } = require('./helpers');
const request = require('supertest');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';

describe('platform basics', () => {
  test('GET /health', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });
  test('unknown route -> JSON 404', async () => {
    const res = await request(app).get(`${api}/nope`);
    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
  });
  test('malformed JSON -> 400 with a useful message (not "Internal server error")', async () => {
    const res = await request(app).post(`${api}/auth/login`).set('Content-Type', 'application/json').send('{bad');
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('Malformed JSON body');
  });
  test('helmet headers on, x-powered-by off', async () => {
    const res = await request(app).get('/health');
    expect(res.headers['x-powered-by']).toBeUndefined();
    expect(res.headers['x-content-type-options']).toBe('nosniff');
  });
  test('swagger UI is served', async () => {
    const res = await request(app).get('/api/docs/');
    expect(res.status).toBe(200);
  });
  test('server errors never leak internals', async () => {
    // DB is not connected -> controller throws a non-operational error.
    const res = await request(app).get(`${api}/businesses`);
    expect(res.status).toBe(500);
    expect(res.body.error.message).toBe('Internal server error');
    expect(JSON.stringify(res.body)).not.toMatch(/mongoose|bufferCommands|at /i);
  });
});

describe('authentication required (401)', () => {
  const protectedRoutes = [
    ['post', '/auth/logout-all'], ['get', '/users/me'], ['patch', '/users/me'], ['post', '/users/me/role'],
    ['post', '/users/me/credentials'], ['post', '/users/me/security-questions'],
    ['get', '/cart'], ['post', '/cart/items'], ['patch', '/cart/items'], ['delete', '/cart'], ['post', '/cart/coupon'],
    ['get', '/orders/mine'], ['post', '/orders'], ['patch', `/orders/${oid()}/status`],
    ['get', '/wishlist'], ['post', '/wishlist/products'], ['post', '/wishlist/businesses'],
    ['get', '/businesses/mine'], ['post', '/businesses'], ['post', `/businesses/${oid()}/verification-documents`],
    ['post', '/products'], ['delete', `/products/${oid()}`],
    ['post', '/reviews'], ['post', `/reviews/${oid()}/reply`],
    ['get', '/admin/verifications'], ['post', `/admin/verifications/${oid()}`],
  ];
  test.each(protectedRoutes)('%s %s without token', async (method, path) => {
    const res = await request(app)[method](api + path).send({});
    expect(res.status).toBe(401);
  });
  test('garbage token', async () => {
    const res = await request(app).get(`${api}/users/me`).set('Authorization', 'Bearer abc.def.ghi');
    expect(res.status).toBe(401);
  });
  test('token signed with the wrong secret', async () => {
    const t = jwt.sign({ id: 'x', role: 'admin' }, 'attacker-secret');
    const res = await request(app).get(`${api}/admin/verifications`).set('Authorization', `Bearer ${t}`);
    expect(res.status).toBe(401);
  });
  test('refresh token cannot be used as an access token', async () => {
    const t = jwt.sign({ id: 'x', role: 'admin' }, process.env.JWT_REFRESH_SECRET);
    const res = await request(app).get(`${api}/admin/verifications`).set('Authorization', `Bearer ${t}`);
    expect(res.status).toBe(401);
  });
  test('expired token', async () => {
    const t = tokenFor('customer', oid().toString(), { expiresIn: -10 });
    const res = await request(app).get(`${api}/users/me`).set('Authorization', `Bearer ${t}`);
    expect(res.status).toBe(401);
  });
  test('alg=none token is rejected', async () => {
    const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const t = `${b64({ alg: 'none', typ: 'JWT' })}.${b64({ id: 'x', role: 'admin' })}.`;
    const res = await request(app).get(`${api}/admin/verifications`).set('Authorization', `Bearer ${t}`);
    expect(res.status).toBe(401);
  });
});

describe('role-based access control (403)', () => {
  test.each([
    ['customer', 'get', '/admin/verifications'],
    ['entrepreneur', 'get', '/admin/verifications'],
    ['customer', 'post', `/admin/verifications/${oid()}`],
    ['customer', 'post', '/businesses'],
    ['customer', 'get', '/businesses/mine'],
    ['customer', 'post', '/products'],
    ['customer', 'delete', `/products/${oid()}`],
    ['admin', 'post', '/orders'],
    ['admin', 'get', '/cart'],
    ['delivery_partner', 'post', '/orders'],
    ['delivery_partner', 'get', '/wishlist'],
    ['customer', 'post', `/reviews/${oid()}/reply`],
  ])('%s %s %s', async (role, method, path) => {
    const res = await request(app)[method](api + path).set(bearer(role)).send({});
    expect(res.status).toBe(403);
  });
});

describe('input validation (422) happens before any DB access', () => {
  const pid = () => oid().toString();
  const goodOrder = () => ({
    businessId: pid(), items: [{ productId: pid(), quantity: 1 }],
    deliveryAddress: { line1: '4th Block', city: 'Bengaluru', pincode: '560011' },
  });

  test('register: bad email / short password / missing contact', async () => {
    expect((await request(app).post(`${api}/auth/register`).send({ name: 'Asha', email: 'nope', password: 'longenough1' })).status).toBe(422);
    expect((await request(app).post(`${api}/auth/register`).send({ name: 'Asha', email: 'a@b.co', password: 'short' })).status).toBe(422);
    expect((await request(app).post(`${api}/auth/register`).send({ name: 'Asha', password: 'longenough1' })).status).toBe(422);
  });
  test('register: privileged role cannot be self-assigned', async () => {
    const res = await request(app).post(`${api}/auth/register`).send({ name: 'Eve', email: 'e@b.co', password: 'longenough1', role: 'admin' });
    expect(res.status).toBe(422);
  });
  test('login: requires an identifier and password', async () => {
    expect((await request(app).post(`${api}/auth/login`).send({ password: 'x' })).status).toBe(422);
    expect((await request(app).post(`${api}/auth/login`).send({ email: 'a@b.co' })).status).toBe(422);
  });
  test('login: NoSQL operator injection is rejected', async () => {
    const res = await request(app).post(`${api}/auth/login`).send({ email: { $gt: '' }, password: 'x' });
    expect(res.status).toBe(422);
  });
  test('refresh without a token -> 400', async () => {
    const res = await request(app).post(`${api}/auth/refresh`).send({});
    expect(res.status).toBe(400);
  });
  test('refresh with garbage token -> 401', async () => {
    const res = await request(app).post(`${api}/auth/refresh`).send({ refreshToken: 'junk' });
    expect(res.status).toBe(401);
  });
  test('refresh rejects an ACCESS token (different secret)', async () => {
    const res = await request(app).post(`${api}/auth/refresh`).send({ refreshToken: tokenFor('customer') });
    expect(res.status).toBe(401);
  });
  test('otp/send and otp/verify validate input before touching Resend or the DB', async () => {
    expect((await request(app).post(`${api}/auth/otp/send`).send({})).status).toBe(422);
    expect((await request(app).post(`${api}/auth/otp/send`).send({ email: 'nope' })).status).toBe(422);
    expect((await request(app).post(`${api}/auth/otp/verify`).send({ email: 'a@b.co' })).status).toBe(422);
    expect((await request(app).post(`${api}/auth/otp/verify`).send({ email: 'a@b.co', otp: '12' })).status).toBe(422);
  });
  test('firebase-exchange requires idToken', async () => {
    expect((await request(app).post(`${api}/auth/firebase-exchange`).send({})).status).toBe(422);
  });

  test.each([
    ['negative quantity', (o) => { o.items[0].quantity = -5; }],
    ['zero quantity', (o) => { o.items[0].quantity = 0; }],
    ['fractional quantity', (o) => { o.items[0].quantity = 1.5; }],
    ['string quantity', (o) => { o.items[0].quantity = 'lots'; }],
    ['no items', (o) => { o.items = []; }],
    ['bad businessId', (o) => { o.businessId = 'not-an-id'; }],
    ['bad productId', (o) => { o.items[0].productId = 'zzz'; }],
    ['delivery without address', (o) => { delete o.deliveryAddress; }],
  ])('POST /orders rejects %s', async (_name, mutate) => {
    const body = goodOrder();
    mutate(body);
    const res = await request(app).post(`${api}/orders`).set(bearer('customer')).send(body);
    expect(res.status).toBe(422);
  });
  test('PATCH /orders/:id/status rejects unknown status', async () => {
    const res = await request(app).patch(`${api}/orders/${oid()}/status`).set(bearer('entrepreneur')).send({ status: 'hacked' });
    expect(res.status).toBe(422);
  });
  test('cart item validation', async () => {
    const h = bearer('customer');
    expect((await request(app).post(`${api}/cart/items`).set(h).send({ productId: 'x' })).status).toBe(422);
    expect((await request(app).post(`${api}/cart/items`).set(h).send({ productId: oid().toString(), quantity: 0 })).status).toBe(422);
    expect((await request(app).post(`${api}/cart/items`).set(h).send({ productId: oid().toString(), quantity: 999 })).status).toBe(422);
    expect((await request(app).post(`${api}/cart/coupon`).set(h).send({})).status).toBe(422);
  });
  test('business create validation', async () => {
    const h = bearer('entrepreneur');
    expect((await request(app).post(`${api}/businesses`).set(h).send({})).status).toBe(422);
    expect((await request(app).post(`${api}/businesses`).set(h).send({ name: 'ok shop', location: { coordinates: [999, 999] } })).status).toBe(422);
  });
  test('verification-documents validation', async () => {
    const h = bearer('entrepreneur');
    const url = `${api}/businesses/${oid()}/verification-documents`;
    expect((await request(app).post(url).set(h).send({ documents: [] })).status).toBe(422);
    expect((await request(app).post(url).set(h).send({ documents: [{ type: 'id_proof', url: 'not a url' }] })).status).toBe(422);
    expect((await request(app).post(url).set(h).send({ documents: [{ type: 'id_proof', url: null }] })).status).toBe(422);
  });
  test('product create validation', async () => {
    const h = bearer('entrepreneur');
    const base = { business: oid().toString(), name: 'Cake', price: 100 };
    expect((await request(app).post(`${api}/products`).set(h).send({ ...base, price: -1 })).status).toBe(422);
    expect((await request(app).post(`${api}/products`).set(h).send({ ...base, stock: -3 })).status).toBe(422);
    expect((await request(app).post(`${api}/products`).set(h).send({ name: 'x', price: 1 })).status).toBe(422);
    expect((await request(app).post(`${api}/products`).set(h).send({ ...base, business: 'nope' })).status).toBe(422);
  });
  test('review validation', async () => {
    const h = bearer('customer');
    expect((await request(app).post(`${api}/reviews`).set(h).send({ productId: oid().toString(), rating: 6 })).status).toBe(422);
    expect((await request(app).post(`${api}/reviews`).set(h).send({ productId: oid().toString(), rating: 0 })).status).toBe(422);
    expect((await request(app).post(`${api}/reviews/${oid()}/reply`).set(bearer('entrepreneur')).send({})).status).toBe(422);
  });
  test('wishlist validation', async () => {
    expect((await request(app).post(`${api}/wishlist/products`).set(bearer('customer')).send({ productId: 'x' })).status).toBe(422);
    expect((await request(app).post(`${api}/wishlist/businesses`).set(bearer('customer')).send({})).status).toBe(422);
  });
  test('admin review validation', async () => {
    const h = bearer('admin');
    expect((await request(app).post(`${api}/admin/verifications/${oid()}`).set(h).send({ action: 'nuke' })).status).toBe(422);
    expect((await request(app).get(`${api}/admin/verifications?status=bogus`).set(h)).status).toBe(422);
    expect((await request(app).get(`${api}/admin/verifications?limit=100000`).set(h)).status).toBe(422);
  });
  test('users: role switch / credentials / security-question input checks', async () => {
    const h = bearer('customer');
    expect((await request(app).post(`${api}/users/me/role`).set(h).send({ role: 'admin' })).status).toBe(422);
    expect((await request(app).post(`${api}/users/me/credentials`).set(h).send({ username: 'abc', password: '123' })).status).toBe(422);
    expect((await request(app).post(`${api}/users/me/credentials`).set(h).send({ username: 'abc', password: { a: 1 } })).status).toBe(422);
    expect((await request(app).post(`${api}/users/me/security-questions`).set(h).send({ answers: 'x' })).status).toBe(422);
    expect((await request(app).post(`${api}/users/me/security-questions`).set(h).send({ answers: { q: 123 } })).status).toBe(422);
  });
  test('businesses/nearby requires valid coordinates', async () => {
    expect((await request(app).get(`${api}/businesses/nearby`)).status).toBe(422);
    expect((await request(app).get(`${api}/businesses/nearby?lat=abc&lng=77`)).status).toBe(422);
    expect((await request(app).get(`${api}/businesses/nearby?lat=95&lng=77`)).status).toBe(422);
  });
  test('product list rejects malformed filters', async () => {
    expect((await request(app).get(`${api}/products?category=nope`)).status).toBe(422);
    expect((await request(app).get(`${api}/products?business=nope`)).status).toBe(422);
  });
});

describe('/images (no Pexels key => placeholders)', () => {
  beforeAll(() => { delete process.env.PEXELS_API_KEY; });
  test('default count', async () => {
    const res = await request(app).get(`${api}/images?q=cake`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(6);
  });
  test.each([['3', 3], ['0', 6], ['-4', 1], ['999', 12], ['abc', 6]])('count=%s -> %i', async (count, n) => {
    const res = await request(app).get(`${api}/images?q=cake&count=${count}`);
    expect(res.body.data).toHaveLength(n);
  });
});

describe('Pexels outage degrades to placeholders', () => {
  const original = global.fetch;
  afterEach(() => { global.fetch = original; delete process.env.PEXELS_API_KEY; });
  test('fetch throws -> still 200', async () => {
    process.env.PEXELS_API_KEY = 'dummy-not-a-real-key';
    global.fetch = jest.fn().mockRejectedValue(new Error('network down'));
    const res = await request(app).get(`${api}/images?q=cake&count=2`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(2);
  });
  test('upstream non-200 -> still 200', async () => {
    process.env.PEXELS_API_KEY = 'dummy-not-a-real-key';
    global.fetch = jest.fn().mockResolvedValue({ ok: false, status: 429 });
    const res = await request(app).get(`${api}/images?q=cake&count=2`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(2);
  });
  test('upstream success is used', async () => {
    process.env.PEXELS_API_KEY = 'dummy-not-a-real-key';
    global.fetch = jest.fn().mockResolvedValue({ ok: true, json: async () => ({ photos: [{ src: { medium: 'https://img/1.jpg' } }] }) });
    const res = await request(app).get(`${api}/images?q=cake&count=1`);
    expect(res.body.data).toEqual(['https://img/1.jpg']);
  });
});
