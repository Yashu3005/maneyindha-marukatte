// Razorpay flow through the real Express app. Stubbed edges: MongoDB (a tiny in-memory Order/
// Transaction/PaymentEvent) and the Razorpay SDK client. Signatures are computed here with
// Node's crypto, independently of the service code, so the tests cannot pass by sharing a bug.
process.env.TRUST_PROXY = '1';
const crypto = require('crypto');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const Order = require('../src/models/Order');
const Transaction = require('../src/models/Transaction');
const PaymentEvent = require('../src/models/PaymentEvent');
const { _setRazorpay } = require('../src/config/razorpay');
const logger = require('../src/utils/logger');
const { oid } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';

const KEY_SECRET = 'test_key_secret_not_real';
const WH_SECRET = 'test_webhook_secret_not_real';
const sign = (secret, data) => crypto.createHmac('sha256', secret).update(data).digest('hex');

const get = (o, path) => path.split('.').reduce((a, k) => (a == null ? a : a[k]), o);
const set = (o, path, v) => { const ks = path.split('.'); let t = o; ks.slice(0, -1).forEach((k) => { t[k] = t[k] || {}; t = t[k]; }); t[ks.at(-1)] = v; };
function matches(row, q) {
  return Object.entries(q).every(([k, v]) => {
    const val = get(row, k);
    if (v && typeof v === 'object' && '$ne' in v) return String(val) !== String(v.$ne);
    if (v === null) return val == null;
    return String(val) === String(v);
  });
}

let orders; let txns; let events; let rzp; let me; let token; let other;
const tokenFor = (id) => jwt.sign({ id, role: 'customer' }, process.env.JWT_SECRET);

function makeOrder(over = {}) {
  const o = { _id: oid(), orderNumber: 'MM1', customer: me, status: 'pending', amounts: { total: 549.1 }, payment: { method: 'razorpay', status: 'pending' }, ...over };
  orders.push(o); return o;
}

beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(logger, 'error').mockImplementation(() => {});
  jest.spyOn(logger, 'warn').mockImplementation(() => {});
  process.env.JWT_SECRET = 'jwt-secret-for-tests-0123456789abcdef';
  process.env.RAZORPAY_KEY_ID = 'rzp_test_dummy';
  process.env.RAZORPAY_KEY_SECRET = KEY_SECRET;
  process.env.RAZORPAY_WEBHOOK_SECRET = WH_SECRET;
  orders = []; txns = []; events = [];
  me = oid(); other = oid(); token = tokenFor(me);
  jest.spyOn(Order, 'findOne').mockImplementation(async (q) => orders.find((r) => matches(r, q)) || null);
  jest.spyOn(Order, 'updateOne').mockImplementation(async (q, u) => {
    const r = orders.find((x) => matches(x, q)); if (!r) return { modifiedCount: 0 };
    Object.entries(u.$set || {}).forEach(([k, v]) => set(r, k, v)); return { modifiedCount: 1 };
  });
  jest.spyOn(Order, 'findOneAndUpdate').mockImplementation(async (q, u) => {
    const r = orders.find((x) => matches(x, q)); if (!r) return null;
    Object.entries(u.$set || {}).forEach(([k, v]) => set(r, k, v)); return r;
  });
  jest.spyOn(Transaction, 'create').mockImplementation(async (d) => { txns.push(d); return d; });
  jest.spyOn(PaymentEvent, 'create').mockImplementation(async (d) => {
    if (events.find((e) => e.eventId === d.eventId)) throw Object.assign(new Error('dup'), { code: 11000 });
    events.push(d); return d;
  });
  jest.spyOn(PaymentEvent, 'deleteOne').mockImplementation(async (q) => { events = events.filter((e) => e.eventId !== q.eventId); });
  rzp = {
    created: [],
    payment: null,
    orders: { create: async (p) => { rzp.created.push(p); return { id: `order_${rzp.created.length}`, amount: p.amount, currency: p.currency }; } },
    payments: { fetch: async () => { if (!rzp.payment) throw Object.assign(new Error('x'), { statusCode: 500 }); return rzp.payment; } },
  };
  _setRazorpay(rzp);
});

const createRzp = (orderId, t = token) => request(app).post(`${api}/payments/razorpay/order`).set('Authorization', `Bearer ${t}`).send({ orderId: String(orderId) });
const verify = (body, t = token) => request(app).post(`${api}/payments/razorpay/verify`).set('Authorization', `Bearer ${t}`).send(body);
const webhook = (event, { secret = WH_SECRET, id = 'evt_1', sig } = {}) => {
  const raw = JSON.stringify(event);
  return request(app).post(`${api}/payments/razorpay/webhook`).set('Content-Type', 'application/json')
    .set('x-razorpay-signature', sig ?? sign(secret, raw)).set('x-razorpay-event-id', id).send(raw);
};
const capturedEvent = (rzpOrderId, paymentId, amount, extra = {}) => ({
  event: 'payment.captured', payload: { payment: { entity: { id: paymentId, order_id: rzpOrderId, amount, currency: 'INR', status: 'captured', ...extra } } },
});

describe('create order', () => {
  test('amount is computed on the server in paise (float-safe) and the secret is never returned', async () => {
    const o = makeOrder();
    const res = await createRzp(o._id);
    expect(res.status).toBe(201);
    expect(rzp.created[0]).toMatchObject({ amount: 54910, currency: 'INR', receipt: 'MM1' });
    expect(res.body.data).toMatchObject({ keyId: 'rzp_test_dummy', razorpayOrderId: 'order_1', amount: 54910 });
    expect(JSON.stringify(res.body)).not.toContain(KEY_SECRET);
  });
  test('client-supplied amount is ignored', async () => {
    const o = makeOrder();
    await request(app).post(`${api}/payments/razorpay/order`).set('Authorization', `Bearer ${token}`).send({ orderId: String(o._id), amount: 1 });
    expect(rzp.created[0].amount).toBe(54910);
  });
  test('idempotent: second call reuses the same Razorpay order', async () => {
    const o = makeOrder();
    await createRzp(o._id); const again = await createRzp(o._id);
    expect(rzp.created).toHaveLength(1);
    expect(again.body.data.razorpayOrderId).toBe('order_1');
  });
  test("another user's order looks like a missing one (404)", async () => {
    const o = makeOrder({ customer: other });
    expect((await createRzp(o._id)).status).toBe(404);
    expect(rzp.created).toHaveLength(0);
  });
  test('rejects COD orders, non-pending orders and paid orders', async () => {
    expect((await createRzp(makeOrder({ payment: { method: 'cod', status: 'pending' } })._id)).status).toBe(422);
    expect((await createRzp(makeOrder({ status: 'cancelled' })._id)).status).toBe(422);
    expect((await createRzp(makeOrder({ payment: { method: 'razorpay', status: 'paid' } })._id)).status).toBe(409);
  });
  test('requires auth and configuration (503 without keys, no leak of values)', async () => {
    const o = makeOrder();
    expect((await request(app).post(`${api}/payments/razorpay/order`).send({ orderId: String(o._id) })).status).toBe(401);
    _setRazorpay(null); delete process.env.RAZORPAY_KEY_ID;
    const res = await createRzp(o._id);
    expect(res.status).toBe(503); expect(res.body.error.code).toBe('PAYMENTS_NOT_CONFIGURED');
  });
  test('provider failure -> 502 without internals', async () => {
    rzp.orders.create = async () => { throw { statusCode: 400, error: { code: 'BAD_REQUEST_ERROR', description: 'secret detail' } }; };
    const res = await createRzp(makeOrder()._id);
    expect(res.status).toBe(502); expect(JSON.stringify(res.body)).not.toContain('secret detail');
  });
});

describe('verify', () => {
  async function started() {
    const o = makeOrder(); await createRzp(o._id);
    return { o, body: (pid, s) => ({ orderId: String(o._id), razorpay_order_id: 'order_1', razorpay_payment_id: pid, razorpay_signature: s ?? sign(KEY_SECRET, `order_1|${pid}`) }) };
  }
  test('valid signature + captured payment -> paid, ledger entry written once', async () => {
    const { o, body } = await started();
    rzp.payment = { id: 'pay_1', order_id: 'order_1', amount: 54910, currency: 'INR', status: 'captured' };
    const res = await verify(body('pay_1'));
    expect(res.status).toBe(200); expect(res.body.data.paymentStatus).toBe('paid');
    expect(o.payment.status).toBe('paid'); expect(txns).toHaveLength(1);
    const again = await verify(body('pay_1'));
    expect(again.body.data.paymentStatus).toBe('paid'); expect(txns).toHaveLength(1);
  });
  test('tampered / malformed signature -> 400 and nothing is paid', async () => {
    const { o, body } = await started();
    rzp.payment = { id: 'pay_1', order_id: 'order_1', amount: 54910, currency: 'INR', status: 'captured' };
    const bad = sign(KEY_SECRET, 'order_1|pay_OTHER');
    expect((await verify(body('pay_1', bad))).status).toBe(400);
    expect((await verify(body('pay_1', 'z'.repeat(64)))).status).toBe(422);
    expect((await verify({ ...body('pay_1'), razorpay_signature: 'abc' })).status).toBe(422);
    expect(o.payment.status).toBe('pending'); expect(txns).toHaveLength(0);
  });
  test('signature made with the wrong secret is rejected', async () => {
    const { body } = await started();
    expect((await verify(body('pay_1', sign('attacker', 'order_1|pay_1')))).status).toBe(400);
  });
  test('uses the stored Razorpay order id, not the client one', async () => {
    const { o } = await started();
    const forged = { orderId: String(o._id), razorpay_order_id: 'order_999', razorpay_payment_id: 'pay_1', razorpay_signature: sign(KEY_SECRET, 'order_999|pay_1') };
    expect((await verify(forged)).status).toBe(400);
  });
  test("cannot verify someone else's order", async () => {
    const { body } = await started();
    expect((await verify(body('pay_1'), tokenFor(other))).status).toBe(404);
  });
  test('amount mismatch is refused', async () => {
    const { o, body } = await started();
    rzp.payment = { id: 'pay_1', order_id: 'order_1', amount: 100, currency: 'INR', status: 'captured' };
    expect((await verify(body('pay_1'))).status).toBe(400);
    expect(o.payment.status).toBe('pending');
  });
  test('authorized-but-not-captured stays pending; failed is recorded; provider outage stays pending', async () => {
    const { o, body } = await started();
    rzp.payment = { id: 'pay_1', order_id: 'order_1', amount: 54910, currency: 'INR', status: 'authorized' };
    expect((await verify(body('pay_1'))).body.data.paymentStatus).toBe('pending');
    rzp.payment = { id: 'pay_1', order_id: 'order_1', amount: 54910, currency: 'INR', status: 'failed', error_description: 'bank declined' };
    expect((await verify(body('pay_1'))).body.data.paymentStatus).toBe('failed');
    expect(o.payment.status).toBe('failed'); expect(o.status).toBe('pending');
    rzp.payment = null; o.payment.status = 'pending';
    const down = await verify(body('pay_1'));
    expect(down.status).toBe(200); expect(down.body.data.paymentStatus).toBe('pending'); expect(txns).toHaveLength(0);
  });
  test('status endpoint reports backend truth and is owner-only', async () => {
    const { o } = await started();
    const res = await request(app).get(`${api}/payments/status/${o._id}`).set('Authorization', `Bearer ${token}`);
    expect(res.body.data).toMatchObject({ paymentStatus: 'pending', orderStatus: 'pending' });
    expect((await request(app).get(`${api}/payments/status/${o._id}`).set('Authorization', `Bearer ${tokenFor(other)}`)).status).toBe(404);
  });
});

describe('webhook', () => {
  async function started() { const o = makeOrder(); await createRzp(o._id); return o; }
  test('rejects missing / wrong / malformed signatures on the raw body', async () => {
    const o = await started(); const ev = capturedEvent('order_1', 'pay_1', 54910);
    expect((await webhook(ev, { sig: '' })).status).toBe(400);
    expect((await webhook(ev, { secret: 'wrong' })).status).toBe(400);
    expect((await webhook(ev, { sig: 'nothex' })).status).toBe(400);
    expect(o.payment.status).toBe('pending'); expect(events).toHaveLength(0);
  });
  test('signature is over the raw bytes: re-serialised JSON with different whitespace fails', async () => {
    await started(); const ev = capturedEvent('order_1', 'pay_1', 54910);
    const sig = sign(WH_SECRET, JSON.stringify(ev));
    const res = await request(app).post(`${api}/payments/razorpay/webhook`).set('Content-Type', 'application/json')
      .set('x-razorpay-signature', sig).set('x-razorpay-event-id', 'e').send(JSON.stringify(ev, null, 2));
    expect(res.status).toBe(400);
  });
  test('payment.captured marks paid; redelivery is deduped; ledger written once', async () => {
    const o = await started(); const ev = capturedEvent('order_1', 'pay_1', 54910);
    expect((await webhook(ev)).status).toBe(200);
    expect(o.payment.status).toBe('paid'); expect(txns).toHaveLength(1);
    const dup = await webhook(ev);
    expect(dup.status).toBe(200); expect(dup.body.data.duplicate).toBe(true); expect(txns).toHaveLength(1);
  });
  test('same payment delivered under a new event id (e.g. order.paid after captured) does not double-fulfil', async () => {
    await started();
    await webhook(capturedEvent('order_1', 'pay_1', 54910), { id: 'evt_a' });
    await webhook({ ...capturedEvent('order_1', 'pay_1', 54910), event: 'order.paid' }, { id: 'evt_b' });
    expect(txns).toHaveLength(1);
  });
  test('amount mismatch is not marked paid', async () => {
    const o = await started();
    const res = await webhook(capturedEvent('order_1', 'pay_1', 1));
    expect(res.status).toBe(200); expect(o.payment.status).toBe('pending'); expect(txns).toHaveLength(0);
  });
  test('payment.failed is recorded but never downgrades a paid order', async () => {
    const o = await started();
    const failed = { event: 'payment.failed', payload: { payment: { entity: { id: 'pay_9', order_id: 'order_1', error_description: 'declined' } } } };
    await webhook(failed, { id: 'f1' }); expect(o.payment.status).toBe('failed');
    await webhook(capturedEvent('order_1', 'pay_1', 54910), { id: 'c1' }); expect(o.payment.status).toBe('paid');
    await webhook(failed, { id: 'f2' }); expect(o.payment.status).toBe('paid');
  });
  test('unknown orders and unhandled events are acknowledged and ignored', async () => {
    await started();
    expect((await webhook(capturedEvent('order_zzz', 'pay_1', 1), { id: 'u1' })).body.data.ignored).toBe('unknown order');
    expect((await webhook({ event: 'refund.created', payload: { payment: { entity: { id: 'p', order_id: 'order_1' } } } }, { id: 'u2' })).status).toBe(200);
  });
  test('internal failure releases the event id so Razorpay can retry', async () => {
    const o = await started();
    jest.spyOn(Transaction, 'create').mockRejectedValueOnce(new Error('db down'));
    const res = await webhook(capturedEvent('order_1', 'pay_1', 54910), { id: 'r1' });
    expect(res.status).toBe(500); expect(events).toHaveLength(0);
    o.payment.status = 'pending';
    expect((await webhook(capturedEvent('order_1', 'pay_1', 54910), { id: 'r1' })).status).toBe(200);
  });
  test('paid after the order was cancelled is flagged for refund', async () => {
    const o = await started(); o.status = 'cancelled';
    await webhook(capturedEvent('order_1', 'pay_1', 54910));
    expect(o.payment.needsRefund).toBe(true);
  });
  test('503 when the webhook secret is not configured', async () => {
    await started(); delete process.env.RAZORPAY_WEBHOOK_SECRET;
    expect((await webhook(capturedEvent('order_1', 'pay_1', 54910))).status).toBe(503);
  });
});
