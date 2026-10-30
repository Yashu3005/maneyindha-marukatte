// Unit tests for order creation/transition rules. Mongoose model STATIC methods are
// stubbed with jest.spyOn (no database); the service logic itself is real.
const { oid } = require('./helpers');
const Order = require('../src/models/Order');
const Product = require('../src/models/Product');
const Business = require('../src/models/Business');
const Cart = require('../src/models/Cart');
const Coupon = require('../src/models/Coupon');
const cartService = require('../src/services/cart.service');
const orderService = require('../src/services/order.service');

const customerId = oid().toString();
const ownerId = oid().toString();
const businessId = oid().toString();
const p1 = { _id: oid(), name: 'Cake', price: 500, stock: 10 };
const p2 = { _id: oid(), name: 'Cookies', price: 200, stock: 4 };

let productUpdates;
beforeEach(() => {
  jest.restoreAllMocks();
  productUpdates = [];
  jest.spyOn(Business, 'findOne').mockResolvedValue({ _id: businessId, isOpen: true });
  jest.spyOn(Product, 'find').mockResolvedValue([p1, p2]);
  jest.spyOn(Product, 'updateOne').mockImplementation(async (filter, update) => {
    productUpdates.push({ filter, update });
    return { modifiedCount: 1 };
  });
  jest.spyOn(Coupon, 'updateOne').mockResolvedValue({ modifiedCount: 1 });
  jest.spyOn(Order, 'create').mockImplementation(async (doc) => ({ ...doc, _id: oid() }));
  jest.spyOn(Cart, 'findOneAndUpdate').mockResolvedValue(null);
});

const place = (items, extra = {}) => orderService.createOrder(customerId, {
  businessId, items, deliveryAddress: { line1: 'x' }, ...extra,
});

describe('createOrder', () => {
  test('prices server-side, adds delivery fee, decrements stock', async () => {
    const order = await place([{ productId: String(p1._id), quantity: 2 }, { productId: String(p2._id), quantity: 1 }]);
    expect(order.amounts).toMatchObject({ subtotal: 1200, deliveryFee: 30, discount: 0, total: 1230 });
    expect(productUpdates.map((u) => u.update.$inc.stock)).toEqual([-2, -1]);
    expect(Cart.findOneAndUpdate).toHaveBeenCalled();
  });
  test('self pickup has no delivery fee and stores no address', async () => {
    const order = await place([{ productId: String(p1._id), quantity: 1 }], { isSelfPickup: true });
    expect(order.amounts.deliveryFee).toBe(0);
    expect(order.deliveryAddress).toBeUndefined();
  });
  test.each([[-5], [0], [1.5], ['abc'], [NaN]])('rejects quantity %p (negative qty used to INCREASE stock)', async (q) => {
    await expect(place([{ productId: String(p1._id), quantity: q }])).rejects.toMatchObject({ statusCode: 422 });
    expect(productUpdates).toHaveLength(0);
  });
  test('merges duplicate lines so stock is checked against the real total', async () => {
    // p2 has stock 4: 3 + 3 = 6 must be refused (previously each line passed on its own)
    await expect(place([{ productId: String(p2._id), quantity: 3 }, { productId: String(p2._id), quantity: 3 }]))
      .rejects.toMatchObject({ statusCode: 422, message: expect.stringMatching(/Insufficient stock/) });
    expect(productUpdates).toHaveLength(0);
  });
  test('duplicate lines that fit are merged into one order line', async () => {
    const order = await place([{ productId: String(p1._id), quantity: 2 }, { productId: String(p1._id), quantity: 3 }]);
    expect(order.items).toHaveLength(1);
    expect(order.items[0].quantity).toBe(5);
    expect(productUpdates).toHaveLength(1);
  });
  test('shop must be approved + active (else 422, nothing reserved)', async () => {
    Business.findOne.mockResolvedValue(null);
    await expect(place([{ productId: String(p1._id), quantity: 1 }])).rejects.toMatchObject({ statusCode: 422 });
    expect(Business.findOne).toHaveBeenCalledWith(expect.objectContaining({ 'verification.status': 'approved', isActive: true }));
    expect(productUpdates).toHaveLength(0);
  });
  test('closed shop is refused', async () => {
    Business.findOne.mockResolvedValue({ _id: businessId, isOpen: false });
    await expect(place([{ productId: String(p1._id), quantity: 1 }])).rejects.toMatchObject({ statusCode: 422 });
  });
  test('unknown product -> 422', async () => {
    await expect(place([{ productId: String(oid()), quantity: 1 }])).rejects.toMatchObject({ statusCode: 422 });
  });
  test('stock race on 2nd line rolls back the 1st line', async () => {
    let call = 0;
    Product.updateOne.mockImplementation(async (filter, update) => {
      productUpdates.push({ filter, update });
      call += 1;
      return { modifiedCount: call === 2 ? 0 : 1 };
    });
    await expect(place([{ productId: String(p1._id), quantity: 2 }, { productId: String(p2._id), quantity: 1 }]))
      .rejects.toMatchObject({ statusCode: 422 });
    // reserve p1(-2), reserve p2 (fails), then restore p1(+2)
    expect(productUpdates.map((u) => u.update.$inc.stock)).toEqual([-2, -1, 2]);
    expect(Order.create).not.toHaveBeenCalled();
  });
  test('Order.create failure restores stock and releases the coupon', async () => {
    const coupon = { _id: oid(), code: 'WELCOME10', type: 'percent', value: 10, maxDiscount: 100 };
    jest.spyOn(cartService, 'validateCoupon').mockResolvedValue(coupon);
    Order.create.mockRejectedValue(new Error('db down'));
    await expect(place([{ productId: String(p1._id), quantity: 1 }], { couponCode: 'WELCOME10' })).rejects.toThrow('db down');
    expect(productUpdates.map((u) => u.update.$inc.stock)).toEqual([-1, 1]);
    expect(Coupon.updateOne).toHaveBeenNthCalledWith(1, expect.anything(), { $inc: { usedCount: 1 } });
    expect(Coupon.updateOne).toHaveBeenNthCalledWith(2, expect.anything(), { $inc: { usedCount: -1 } });
  });
  test('coupon usage is only counted if the order is actually created', async () => {
    const coupon = { _id: oid(), code: 'WELCOME10', type: 'percent', value: 10, maxDiscount: 100 };
    jest.spyOn(cartService, 'validateCoupon').mockResolvedValue(coupon);
    const order = await place([{ productId: String(p1._id), quantity: 1 }], { couponCode: 'WELCOME10' });
    expect(order.coupon).toEqual({ code: 'WELCOME10', discount: 50 });
    expect(order.amounts.total).toBe(500 - 50 + 30);
    expect(Coupon.updateOne).toHaveBeenCalledTimes(1);
  });
  test('coupon exhausted concurrently -> 422 and stock restored', async () => {
    const coupon = { _id: oid(), code: 'ONCE', type: 'flat', value: 50, usageLimitTotal: 1 };
    jest.spyOn(cartService, 'validateCoupon').mockResolvedValue(coupon);
    Coupon.updateOne.mockResolvedValue({ modifiedCount: 0 });
    await expect(place([{ productId: String(p1._id), quantity: 1 }], { couponCode: 'ONCE' }))
      .rejects.toMatchObject({ statusCode: 422, message: 'Coupon usage limit reached' });
    expect(Coupon.updateOne).toHaveBeenCalledWith({ _id: coupon._id, usedCount: { $lt: 1 } }, { $inc: { usedCount: 1 } });
    expect(productUpdates.map((u) => u.update.$inc.stock)).toEqual([-1, 1]);
  });
});

describe('transition authorization', () => {
  const partnerId = oid().toString();
  const strangerId = oid().toString();
  const mk = (status, over = {}) => ({
    _id: oid(), status, customer: customerId, business: businessId, deliveryPartner: partnerId,
    items: [{ product: p1._id, quantity: 2 }], coupon: undefined, ...over,
  });
  const as = (id, role = 'customer') => ({ id, role });
  let current;
  beforeEach(() => {
    current = mk('pending');
    jest.spyOn(Order, 'findById').mockImplementation(async () => current);
    jest.spyOn(Business, 'exists').mockImplementation(async (q) => (q.owner === ownerId ? { _id: businessId } : null));
    jest.spyOn(Order, 'findOneAndUpdate').mockImplementation(async (_f, u) => ({ ...current, status: u.$set.status }));
  });

  test('unknown order -> 404', async () => {
    Order.findById.mockResolvedValue(null);
    await expect(orderService.transition('x', 'confirmed', as(ownerId, 'entrepreneur'))).rejects.toMatchObject({ statusCode: 404 });
  });
  test('stranger gets 404 (cannot probe order ids) and nothing is written', async () => {
    await expect(orderService.transition('x', 'confirmed', as(strangerId, 'entrepreneur'))).rejects.toMatchObject({ statusCode: 404 });
    await expect(orderService.transition('x', 'cancelled', as(strangerId))).rejects.toMatchObject({ statusCode: 404 });
    expect(Order.findOneAndUpdate).not.toHaveBeenCalled();
  });
  test('a random entrepreneur (not this shop) cannot confirm', async () => {
    await expect(orderService.transition('x', 'confirmed', as(oid().toString(), 'entrepreneur'))).rejects.toMatchObject({ statusCode: 404 });
  });
  test('shop owner can confirm', async () => {
    const o = await orderService.transition('x', 'confirmed', as(ownerId, 'entrepreneur'));
    expect(o.status).toBe('confirmed');
    expect(Order.findOneAndUpdate).toHaveBeenCalledWith(
      { _id: current._id, status: 'pending' }, expect.objectContaining({ $set: { status: 'confirmed' } }), { new: true });
  });
  test('shop owner can walk the happy path ready -> picked_up -> out_for_delivery -> delivered', async () => {
    for (const [from, to] of [['ready', 'picked_up'], ['picked_up', 'out_for_delivery'], ['out_for_delivery', 'delivered']]) {
      current = mk(from);
      expect((await orderService.transition('x', to, as(ownerId, 'entrepreneur'))).status).toBe(to);
    }
  });
  test('customer may NOT confirm / deliver their own order (self-fulfilment fraud)', async () => {
    await expect(orderService.transition('x', 'confirmed', as(customerId))).rejects.toMatchObject({ statusCode: 403 });
    current = mk('out_for_delivery');
    await expect(orderService.transition('x', 'delivered', as(customerId))).rejects.toMatchObject({ statusCode: 403 });
  });
  test('customer may cancel while pending/confirmed, not later', async () => {
    expect((await orderService.transition('x', 'cancelled', as(customerId))).status).toBe('cancelled');
    current = mk('confirmed');
    expect((await orderService.transition('x', 'cancelled', as(customerId))).status).toBe('cancelled');
    current = mk('preparing');
    await expect(orderService.transition('x', 'cancelled', as(customerId))).rejects.toMatchObject({ statusCode: 403 });
  });
  test('shop owner cannot refund; only admin can', async () => {
    current = mk('delivered');
    await expect(orderService.transition('x', 'refunded', as(ownerId, 'entrepreneur'))).rejects.toMatchObject({ statusCode: 403 });
    await expect(orderService.transition('x', 'refunded', as(customerId))).rejects.toMatchObject({ statusCode: 403 });
    expect((await orderService.transition('x', 'refunded', as(oid().toString(), 'admin'))).status).toBe('refunded');
  });
  test('assigned delivery partner can advance delivery steps but not confirm', async () => {
    current = mk('picked_up');
    expect((await orderService.transition('x', 'out_for_delivery', as(partnerId, 'delivery_partner'))).status).toBe('out_for_delivery');
    current = mk('pending');
    await expect(orderService.transition('x', 'confirmed', as(partnerId, 'delivery_partner'))).rejects.toMatchObject({ statusCode: 403 });
  });
  test('illegal state jumps are still refused for permitted users (422)', async () => {
    await expect(orderService.transition('x', 'delivered', as(ownerId, 'entrepreneur'))).rejects.toMatchObject({ statusCode: 422 });
    current = mk('delivered');
    await expect(orderService.transition('x', 'preparing', as(oid().toString(), 'admin'))).rejects.toMatchObject({ statusCode: 422 });
  });
  test('lost compare-and-set race -> 409', async () => {
    Order.findOneAndUpdate.mockResolvedValue(null);
    await expect(orderService.transition('x', 'confirmed', as(ownerId, 'entrepreneur'))).rejects.toMatchObject({ statusCode: 409 });
  });
  test('cancelling / rejecting restores stock exactly once', async () => {
    productUpdates = [];
    await orderService.transition('x', 'cancelled', as(customerId));
    expect(productUpdates).toEqual([{ filter: { _id: p1._id }, update: { $inc: { stock: 2 } } }]);
    productUpdates.length = 0;
    await orderService.transition('x', 'rejected', as(ownerId, 'entrepreneur'));
    expect(productUpdates).toHaveLength(1);
  });
  test('non-releasing transitions do not touch stock', async () => {
    await orderService.transition('x', 'confirmed', as(ownerId, 'entrepreneur'));
    expect(productUpdates).toHaveLength(0);
  });
  test('cancelling an order that used a coupon gives the use back', async () => {
    current = mk('pending', { coupon: { code: 'WELCOME10', discount: 50 } });
    const couponId = oid();
    jest.spyOn(Coupon, 'findOne').mockReturnValue({ select: async () => ({ _id: couponId }) });
    await orderService.transition('x', 'cancelled', as(customerId));
    expect(Coupon.updateOne).toHaveBeenCalledWith({ _id: couponId, usedCount: { $gt: 0 } }, { $inc: { usedCount: -1 } });
  });
});

describe('order lists: placed vs received', () => {
  const Business = require('../src/models/Business');
  const run = async (fn, role, owned = [{ _id: 'shopA' }]) => {
    const calls = [];
    const finds = [];
    const q = { sort: () => q, limit: () => q, populate: (...a) => { calls.push(a); return q; }, then: (res) => res([]) };
    jest.spyOn(Order, 'find').mockImplementation((f) => { finds.push(f); return q; });
    jest.spyOn(Business, 'find').mockReturnValue({ select: async () => owned });
    await orderService[fn]({ id: 'u1', role });
    return { calls, finds };
  };
  test('"my orders" is only what the user placed, even for a shop owner, and never exposes other customers', async () => {
    const r = await run('ordersForUser', 'entrepreneur');
    expect(r.finds).toEqual([{ customer: 'u1' }]);
    expect(r.calls).not.toContainEqual(['customer', 'name phone']);
    expect((await run('ordersForUser', 'customer')).finds).toEqual([{ customer: 'u1' }]);
    expect((await run('ordersForUser', 'delivery_partner')).finds).toEqual([{ deliveryPartner: 'u1' }]);
  });
  test('"received" is only orders for the owner\'s own shops, with the customer name and phone', async () => {
    const r = await run('receivedOrders', 'entrepreneur', [{ _id: 'shopA' }, { _id: 'shopB' }]);
    expect(r.finds).toEqual([{ business: { $in: ['shopA', 'shopB'] } }]);
    expect(r.calls).toContainEqual(['customer', 'name phone']);
  });
  test('an owner with no shop receives nothing (and no order query runs)', async () => {
    const r = await run('receivedOrders', 'entrepreneur', []);
    expect(r.finds).toEqual([]);
  });
});
