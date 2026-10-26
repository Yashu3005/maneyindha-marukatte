// Controller-level tests with model statics stubbed (no database).
const { oid } = require('./helpers');
const bcrypt = require('bcryptjs');
const Business = require('../src/models/Business');
const Category = require('../src/models/Category');
const Product = require('../src/models/Product');
const Cart = require('../src/models/Cart');
const User = require('../src/models/User');
const businessController = require('../src/controllers/business.controller');
const productController = require('../src/controllers/product.controller');
const usersController = require('../src/controllers/users.controller');
const cartService = require('../src/services/cart.service');
const RefreshSession = require('../src/models/RefreshSession');
const { installMemoryModel } = require('./fakes/memoryModel');

function run(handler, req) {
  return new Promise((resolve) => {
    const res = {
      statusCode: 200,
      status(c) { this.statusCode = c; return this; },
      json(b) { this.body = b; resolve({ status: this.statusCode, body: b }); },
    };
    handler({ params: {}, query: {}, body: {}, ...req }, res, (err) => resolve({ error: err }));
  });
}

beforeEach(() => jest.restoreAllMocks());

describe('POST /businesses mass-assignment', () => {
  test('client cannot self-approve, pick owner, or set rating', async () => {
    const me = oid().toString();
    let saved;
    jest.spyOn(Business, 'create').mockImplementation(async (d) => { saved = d; return { ...d, _id: oid() }; });
    const { status } = await run(businessController.create, {
      user: { id: me, role: 'entrepreneur' },
      body: {
        name: "Asha's Shop", description: 'd',
        verification: { status: 'approved' }, owner: oid().toString(),
        rating: { avg: 5, count: 999 }, isActive: false, followerCount: 1e6, 'verification.status': 'approved',
      },
    });
    expect(status).toBe(201);
    expect(saved.owner).toBe(me);
    for (const k of ['verification', 'rating', 'isActive', 'followerCount', 'verification.status']) {
      expect(saved).not.toHaveProperty(k);
    }
    expect(saved.slug).toMatch(/^asha-s-shop-/);
    // No fabricated default location any more.
    expect(saved.location).toBeUndefined();
    expect(saved.locationSource).toBe('unset');
  });
  test('category NAME resolves to an id without renaming an existing category', async () => {
    const catId = oid();
    jest.spyOn(Category, 'findOneAndUpdate').mockResolvedValue({ _id: catId });
    let saved;
    jest.spyOn(Business, 'create').mockImplementation(async (d) => { saved = d; return d; });
    await run(businessController.create, { user: { id: 'u' }, body: { name: 'Shop', category: 'Baking' } });
    expect(Category.findOneAndUpdate).toHaveBeenCalledWith(
      { slug: 'baking' }, { $setOnInsert: { name: 'Baking', slug: 'baking', isActive: true } }, { upsert: true, new: true });
    expect(saved.category).toBe(catId);
  });
});

describe('business visibility & document privacy', () => {
  const owner = oid();
  const doc = (status) => {
    const o = { _id: oid(), owner, isActive: true, name: 'S',
      verification: { status, documents: [{ type: 'id_proof', url: 'https://secret/aadhaar.jpg' }], reviewedBy: oid(), rejectionReason: 'r' } };
    return { ...o, toObject: () => JSON.parse(JSON.stringify(o)) };
  };
  const stub = (d) => jest.spyOn(Business, 'findById').mockReturnValue({ populate: async () => d });
  const leaks = (b) => JSON.stringify(b).includes('aadhaar');

  test('anonymous: approved shop is visible WITHOUT verification documents', async () => {
    stub(doc('approved'));
    const { status, body } = await run(businessController.getById, { params: { id: 'x' } });
    expect(status).toBe(200);
    expect(leaks(body)).toBe(false);
    expect(body.data.verification.status).toBe('approved');
  });
  test('anonymous / other customer: unapproved shop is 404', async () => {
    stub(doc('in_review'));
    expect((await run(businessController.getById, { params: { id: 'x' } })).error.statusCode).toBe(404);
    expect((await run(businessController.getById, { params: { id: 'x' }, user: { id: oid().toString(), role: 'customer' } })).error.statusCode).toBe(404);
  });
  test('owner and admin can see an unapproved shop including documents', async () => {
    stub(doc('in_review'));
    const asOwner = await run(businessController.getById, { params: { id: 'x' }, user: { id: owner.toString(), role: 'entrepreneur' } });
    expect(leaks(asOwner.body)).toBe(true);
    const asAdmin = await run(businessController.getById, { params: { id: 'x' }, user: { id: oid().toString(), role: 'admin' } });
    expect(asAdmin.status).toBe(200);
  });
  test('inactive shop is 404 for everyone', async () => {
    const d = doc('approved'); d.isActive = false;
    stub(d);
    expect((await run(businessController.getById, { params: { id: 'x' }, user: { id: owner.toString(), role: 'entrepreneur' } })).error.statusCode).toBe(404);
  });
  test('list and nearby strip documents via select()', async () => {
    const chain = (result) => {
      const c = {};
      for (const m of ['select', 'sort', 'skip', 'limit', 'populate']) c[m] = jest.fn(() => c);
      c.then = (res, rej) => Promise.resolve(result).then(res, rej);
      return c;
    };
    const listChain = chain([]);
    jest.spyOn(Business, 'find').mockReturnValue(listChain);
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(0);
    await run(businessController.list, {});
    expect(listChain.select).toHaveBeenCalledWith(expect.stringContaining('-verification.documents'));
    listChain.select.mockClear();
    await run(businessController.nearby, { query: { lat: '12.9', lng: '77.5' } });
    expect(listChain.select).toHaveBeenCalledWith(expect.stringContaining('-verification.documents'));
  });
  test('nearby clamps radius and page size', async () => {
    const c = {}; for (const m of ['select', 'skip', 'limit']) c[m] = jest.fn(() => c);
    c.then = (r) => Promise.resolve([]).then(r);
    const find = jest.spyOn(Business, 'find').mockReturnValue(c);
    await run(businessController.nearby, { query: { lat: '12', lng: '77', radiusKm: '999999', limit: '99999' } });
    expect(find.mock.calls[0][0].publicLocation.$near.$maxDistance).toBe(200 * 1000);
    expect(c.limit).toHaveBeenCalledWith(50);
  });
});

describe('products', () => {
  test('create ignores client-supplied rating / isActive / deletedAt', async () => {
    const biz = oid();
    jest.spyOn(Business, 'findOne').mockResolvedValue({ _id: biz });
    let saved;
    jest.spyOn(Product, 'create').mockImplementation(async (d) => { saved = d; return d; });
    await run(productController.create, {
      user: { id: 'u' },
      body: { business: biz.toString(), name: 'Cake', price: 10, rating: { avg: 5, count: 1000 }, isActive: false, deletedAt: new Date() },
    });
    expect(saved).toEqual({ business: biz.toString(), name: 'Cake', price: 10 });
  });
  test('create on someone else\'s shop -> 403', async () => {
    jest.spyOn(Business, 'findOne').mockResolvedValue(null);
    expect((await run(productController.create, { user: { id: 'u' }, body: { business: oid().toString() } })).error.statusCode).toBe(403);
  });

  const shop = (status, owner = oid()) => ({ _id: oid(), owner, verification: { status } });
  const findChain = () => {
    const c = {}; for (const m of ['sort', 'skip', 'limit']) c[m] = jest.fn(() => c);
    c.then = (r) => Promise.resolve([{ name: 'P' }]).then(r);
    return c;
  };
  test('catalogue of an UNAPPROVED shop is hidden from the public but visible to its owner', async () => {
    const owner = oid();
    jest.spyOn(Business, 'findOne').mockReturnValue({ select: async () => shop('pending', owner) });
    const find = jest.spyOn(Product, 'find').mockReturnValue(findChain());
    jest.spyOn(Product, 'countDocuments').mockResolvedValue(1);
    const q = { business: oid().toString() };
    expect((await run(productController.list, { query: q })).body.data).toEqual([]);
    expect(find).not.toHaveBeenCalled();
    expect((await run(productController.list, { query: q, user: { id: oid().toString(), role: 'customer' } })).body.data).toEqual([]);
    expect((await run(productController.list, { query: q, user: { id: owner.toString(), role: 'entrepreneur' } })).body.data).toHaveLength(1);
  });
  test('approved shop catalogue is public; limit/sort are sanitised', async () => {
    jest.spyOn(Business, 'findOne').mockReturnValue({ select: async () => shop('approved') });
    const chain = findChain();
    jest.spyOn(Product, 'find').mockReturnValue(chain);
    jest.spyOn(Product, 'countDocuments').mockResolvedValue(1);
    const { body } = await run(productController.list, { query: { business: oid().toString(), limit: '1000000', sort: 'passwordHash' } });
    expect(body.data).toHaveLength(1);
    expect(chain.limit).toHaveBeenCalledWith(50);
    expect(chain.sort).toHaveBeenCalledWith('-createdAt');
  });
  test('getById: product of unapproved shop is 404 for strangers; shape is preserved for the public', async () => {
    const mk = (status) => {
      const business = { _id: oid(), name: 'S', slug: 's', rating: { avg: 4 }, owner: oid(), isActive: true, verification: { status } };
      const p = { _id: oid(), isActive: true, name: 'P', business };
      return { ...p, toObject: () => ({ ...p }) };
    };
    const stub = (p) => jest.spyOn(Product, 'findById').mockReturnValue({ populate: async () => p });
    stub(mk('pending'));
    expect((await run(productController.getById, { params: { id: 'x' } })).error.statusCode).toBe(404);
    stub(mk('approved'));
    const { body } = await run(productController.getById, { params: { id: 'x' } });
    expect(Object.keys(body.data.business).sort()).toEqual(['_id', 'name', 'rating', 'slug']);
  });
});

describe('cart', () => {
  test('cannot add products from an unapproved shop', async () => {
    jest.spyOn(Product, 'findOne').mockResolvedValue({ _id: oid(), business: oid(), stock: 5 });
    jest.spyOn(Business, 'findOne').mockReturnValue({ select: async () => null });
    await expect(cartService.addItem('c', { productId: 'p', quantity: 1 })).rejects.toMatchObject({ statusCode: 404 });
  });
  test('stock is checked against existing cart quantity + increment', async () => {
    const pid = oid();
    jest.spyOn(Product, 'findOne').mockResolvedValue({ _id: pid, business: oid(), stock: 5 });
    jest.spyOn(Business, 'findOne').mockReturnValue({ select: async () => ({ _id: 1 }) });
    const cart = { business: undefined, items: [{ product: pid, quantity: 4 }], save: jest.fn() };
    jest.spyOn(Cart, 'findOne').mockResolvedValue(cart);
    await expect(cartService.addItem('c', { productId: String(pid), quantity: 2 }))
      .rejects.toMatchObject({ statusCode: 422, message: 'Insufficient stock' });
    expect(cart.save).not.toHaveBeenCalled();
  });
  test('updateItem cannot raise quantity above stock', async () => {
    const pid = oid();
    const cart = { items: [{ product: pid, quantity: 1 }], save: jest.fn() };
    jest.spyOn(Cart, 'findOne').mockResolvedValue(cart);
    jest.spyOn(Product, 'findById').mockReturnValue({ select: async () => ({ stock: 3 }) });
    await expect(cartService.updateItem('c', { productId: String(pid), quantity: 10 })).rejects.toMatchObject({ statusCode: 422 });
    expect(cart.items[0].quantity).toBe(1);
  });
});

describe('users', () => {
  const user = (role) => ({ _id: oid(), role, save: jest.fn() });
  test.each(['admin', 'super_admin', 'delivery_partner'])('%s cannot use the customer/entrepreneur toggle (would silently demote them)', async (role) => {
    const u = user(role);
    jest.spyOn(User, 'findById').mockResolvedValue(u);
    const { error } = await run(usersController.switchRole, { user: { id: 'x' }, body: { role: 'customer' } });
    expect(error.statusCode).toBe(403);
    expect(u.role).toBe(role);
    expect(u.save).not.toHaveBeenCalled();
  });
  test('customer -> entrepreneur still works and returns fresh tokens', async () => {
    const u = { ...user('customer'), name: 'n' };
    installMemoryModel(RefreshSession);
    jest.spyOn(User, 'findById').mockResolvedValue(u);
    jest.spyOn(Business, 'exists').mockResolvedValue(null);
    const { body } = await run(usersController.switchRole, { user: { id: 'x' }, body: { role: 'entrepreneur' } });
    expect(u.role).toBe('entrepreneur');
    expect(body.data.accessToken).toBeTruthy();
    expect(body.data.hasBusiness).toBe(false);
  });
  test('security answers are stored hashed, case-insensitively', async () => {
    const u = user('customer');
    jest.spyOn(User, 'findById').mockResolvedValue(u);
    await run(usersController.setSecurityQuestions, { user: { id: 'x' }, body: { answers: { pet: '  Rover ' } } });
    expect(u.securityQuestions.pet).not.toMatch(/rover/i);
    expect(await bcrypt.compare('rover', u.securityQuestions.pet)).toBe(true);
  });
});
