// The single administrator: credentials from server configuration, no second way to become admin.
process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const User = require('../src/models/User');
const RefreshSession = require('../src/models/RefreshSession');
const adminService = require('../src/services/admin.service');
const logger = require('../src/utils/logger');
const { hashPassword, verifyPassword, MIN_LENGTH } = require('../src/utils/adminPassword');
const { oid, bearer, tokenFor, ADMIN, installAdmin, adminBearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';
const PASSWORD = 'correct horse battery staple';
let hash;

beforeAll(async () => { hash = await hashPassword(PASSWORD); });
beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(logger, 'warn').mockImplementation(() => {});
  process.env.ADMIN_USERNAME = 'Sadan-Admin';
  process.env.ADMIN_PASSWORD_HASH = hash;
  jest.spyOn(RefreshSession, 'findOneAndUpdate').mockResolvedValue({});
  jest.spyOn(RefreshSession, 'deleteMany').mockResolvedValue({});
});

describe('password hashing', () => {
  test('round-trips; wrong password, short password and garbage fail closed', async () => {
    expect(await verifyPassword(PASSWORD, hash)).toBe(true);
    expect(await verifyPassword(`${PASSWORD}x`, hash)).toBe(false);
    for (const bad of [undefined, '', 'plain', 'scrypt:1:2:3', 'scrypt:16384:AAAA:AAAA', 'bcrypt:16384:AAAA:AAAA']) {
      expect(await verifyPassword(PASSWORD, bad)).toBe(false);
    }
    await expect(hashPassword('short')).rejects.toThrow(String(MIN_LENGTH));
  });
  test('uses a fresh salt each time and keeps "$" out of the value', async () => {
    const other = await hashPassword(PASSWORD);
    expect(other).not.toBe(hash);
    expect(hash).not.toContain('$');
    expect(hash.startsWith('scrypt:')).toBe(true);
  });
});

describe('POST /auth/admin/login', () => {
  const login = (body) => request(app).post(`${api}/auth/admin/login`).send(body);
  let saved;
  beforeEach(() => {
    saved = [];
    jest.spyOn(User, 'findOne').mockResolvedValue(null);
    jest.spyOn(User.prototype, 'save').mockImplementation(async function save() { saved.push(this); return this; });
    jest.spyOn(User, 'updateOne').mockResolvedValue({});
    jest.spyOn(User, 'updateMany').mockResolvedValue({});
    jest.spyOn(User, 'find').mockReturnValue({ select: async () => [] });
  });

  test('correct credentials -> admin session; the username is case-insensitive; no password is stored', async () => {
    const res = await login({ username: 'SADAN-admin', password: PASSWORD });
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.body.data.user.role).toBe('admin');
    expect(res.body.data.user.username).toBe('sadan-admin');
    const claims = jwt.verify(res.body.data.accessToken, process.env.JWT_SECRET);
    expect(claims.role).toBe('admin');
    expect(saved).toHaveLength(1);
    expect(saved[0].passwordHash).toBeUndefined();
    expect(User.updateOne).toHaveBeenCalledWith({ _id: saved[0]._id }, { $unset: { passwordHash: 1 } });
    expect(JSON.stringify(res.body)).not.toContain(PASSWORD);
    expect(JSON.stringify(res.body)).not.toContain(hash);
  });

  test('wrong password and wrong username get the same 401', async () => {
    const a = await login({ username: 'sadan-admin', password: 'nope-nope-nope' });
    const b = await login({ username: 'someone-else', password: PASSWORD });
    expect(a.status).toBe(401);
    expect(b.status).toBe(401);
    expect(a.body.error.message).toBe(b.body.error.message);
    expect(saved).toHaveLength(0);
  });

  test('not configured -> 503, never a default login', async () => {
    delete process.env.ADMIN_PASSWORD_HASH;
    const res = await login({ username: 'sadan-admin', password: PASSWORD });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('ADMIN_NOT_CONFIGURED');
    process.env.ADMIN_PASSWORD_HASH = hash;
    delete process.env.ADMIN_USERNAME;
    expect((await login({ username: '', password: PASSWORD })).status).toBe(422); // validation first
    expect((await login({ username: 'x', password: PASSWORD })).status).toBe(503);
  });

  test('a normal member holding the username is never promoted', async () => {
    User.findOne.mockResolvedValue({ role: 'customer', username: 'sadan-admin' });
    const res = await login({ username: 'sadan-admin', password: PASSWORD });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ADMIN_USERNAME_TAKEN');
    expect(saved).toHaveLength(0);
  });

  test('any other account with an admin role is demoted and signed out', async () => {
    const stale = oid();
    User.find.mockReturnValue({ select: async () => [{ _id: stale }] });
    const res = await login({ username: 'sadan-admin', password: PASSWORD });
    expect(res.status).toBe(200);
    expect(User.updateMany).toHaveBeenCalledWith({ _id: { $in: [stale] } }, { $set: { role: 'customer' } });
    expect(RefreshSession.deleteMany).toHaveBeenCalledWith({ user: { $in: [stale] } });
  });

  test('input is validated and the endpoint is rate limited', async () => {
    expect((await login({})).status).toBe(422);
    expect((await login({ username: 'a', password: 'x'.repeat(300) })).status).toBe(422);
    const codes = [];
    for (let i = 0; i < 12; i += 1) codes.push((await login({ username: 'sadan-admin', password: 'wrong-wrong-1' })).status);
    expect(codes).toContain(429);
  });
});

describe('only the configured administrator reaches the admin area', () => {
  beforeEach(() => {
    jest.spyOn(adminService, 'listVerificationRequests').mockResolvedValue({ items: [], meta: { page: 1, limit: 20, total: 0 } });
  });
  const get = (headers) => request(app).get(`${api}/admin/verifications`).set(headers);

  test('the configured admin gets in', async () => {
    installAdmin(User);
    expect((await get({ Authorization: adminBearer().Authorization })).status).toBe(200);
  });
  test('a token that merely CLAIMS admin is not enough when it is not the configured admin', async () => {
    installAdmin(User);
    const stranger = bearer('admin', String(oid()));
    expect((await get(stranger)).status).toBe(403);
    expect(adminService.listVerificationRequests).not.toHaveBeenCalled();
  });
  test('wrong username, suspended, or demoted admin accounts are refused', async () => {
    for (const opts of [{ username: 'another-admin' }, { isActive: false }, { role: 'customer' }]) {
      installAdmin(User, opts);
      expect((await get(adminBearer())).status).toBe(403);
    }
  });
  test('customers and entrepreneurs never reach the database check', async () => {
    const spy = jest.spyOn(User, 'findById');
    expect((await get(bearer('customer'))).status).toBe(403);
    expect((await get(bearer('entrepreneur'))).status).toBe(403);
    expect(spy).not.toHaveBeenCalled();
    expect((await request(app).get(`${api}/admin/verifications`)).status).toBe(401);
  });
  test('admin env missing -> nobody is admin', async () => {
    installAdmin(User);
    delete process.env.ADMIN_USERNAME;
    expect((await get({ Authorization: tokenFor('admin', ADMIN.id) && `Bearer ${tokenFor('admin', ADMIN.id)}` })).status).toBe(403);
  });
});

describe('no other door to admin', () => {
  test('password login refuses an admin-role account', async () => {
    jest.spyOn(User, 'findOne').mockReturnValue({
      select: async () => ({ _id: oid(), role: 'admin', isActive: true, passwordHash: bcrypt.hashSync('pw-12345678', 4) }),
    });
    const res = await request(app).post(`${api}/auth/login`).send({ email: 'a@b.co', password: 'pw-12345678' });
    expect(res.status).toBe(401);
  });
  test('registration cannot pick an admin role', async () => {
    const res = await request(app).post(`${api}/auth/register`).send({ name: 'Eve', email: 'e@b.co', password: 'longenough1', role: 'admin' });
    expect(res.status).toBe(422);
  });
  test('nobody can take the administrator\'s username', async () => {
    const user = { _id: oid(), save: jest.fn() };
    jest.spyOn(User, 'findById').mockResolvedValue(user);
    const res = await request(app).post(`${api}/users/me/credentials`).set(bearer('customer'))
      .send({ username: 'SADAN-ADMIN', password: 'longenough1' });
    expect(res.status).toBe(409);
    expect(user.save).not.toHaveBeenCalled();
  });
});
