// authService: what happens AFTER an OTP is proven — account creation/linking, privileged
// accounts, sessions, refresh and logout.
const { oid } = require('./helpers');
const { installMemoryModel } = require('./fakes/memoryModel');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const User = require('../src/models/User');
const RefreshSession = require('../src/models/RefreshSession');
const otpService = require('../src/services/otp.service');
const authService = require('../src/services/auth.service');

const email = 'otp-user@example.com';
const dbUser = (over = {}) => ({ _id: oid(), name: 'C', email, role: 'customer', isActive: true, emailVerified: false, save: jest.fn(), ...over });
let sessions;

beforeEach(() => {
  jest.restoreAllMocks();
  sessions = installMemoryModel(RefreshSession);
  jest.spyOn(otpService, 'verifyOtp').mockResolvedValue(email);
});

describe('verifyOtp (after the code is proven)', () => {
  test('unknown email -> new verified customer + session; nothing about demo codes remains', async () => {
    jest.spyOn(User, 'findOne').mockResolvedValue(null);
    jest.spyOn(User, 'create').mockImplementation(async (d) => ({ _id: oid(), isActive: true, ...d }));
    const res = await authService.verifyOtp({ email, otp: '123456' });
    expect(res.isNewUser).toBe(true);
    expect(User.create).toHaveBeenCalledWith(expect.objectContaining({ email, emailVerified: true, role: 'customer', profileComplete: false }));
    expect(res.user.emailVerified).toBe(true);
    expect(sessions).toHaveLength(1);
    expect(jwt.verify(res.accessToken, process.env.JWT_SECRET).sid).toBe(sessions[0].sid);
  });
  test('existing account gets its email marked verified and keeps its role', async () => {
    const u = dbUser({ role: 'entrepreneur' });
    jest.spyOn(User, 'findOne').mockResolvedValue(u);
    const res = await authService.verifyOtp({ email, otp: '123456' });
    expect(res.isNewUser).toBe(false);
    expect(u.emailVerified).toBe(true);
    expect(u.save).toHaveBeenCalled();
    expect(jwt.verify(res.accessToken, process.env.JWT_SECRET)).toMatchObject({ id: String(u._id), role: 'entrepreneur' });
  });
  test('the session is for the right account (no cross-account tokens)', async () => {
    const u = dbUser();
    jest.spyOn(User, 'findOne').mockResolvedValue(u);
    const res = await authService.verifyOtp({ email, otp: '123456' });
    expect(String(sessions[0].user)).toBe(String(u._id));
    expect(res.user.id).toBe(u._id);
  });
  test.each(['admin', 'super_admin'])('OTP can never sign into a %s account', async (role) => {
    jest.spyOn(User, 'findOne').mockResolvedValue(dbUser({ role }));
    await expect(authService.verifyOtp({ email, otp: '123456' })).rejects.toMatchObject({ statusCode: 403 });
    expect(sessions).toHaveLength(0);
  });
  test('disabled accounts are refused and get no session', async () => {
    jest.spyOn(User, 'findOne').mockResolvedValue(dbUser({ isActive: false, emailVerified: true }));
    await expect(authService.verifyOtp({ email, otp: '123456' })).rejects.toMatchObject({ statusCode: 403 });
    expect(sessions).toHaveLength(0);
  });
  test('a failed code verification creates no user and no session', async () => {
    otpService.verifyOtp.mockRejectedValue(Object.assign(new Error('Invalid or expired code'), { statusCode: 401 }));
    jest.spyOn(User, 'findOne');
    jest.spyOn(User, 'create');
    await expect(authService.verifyOtp({ email, otp: '000000' })).rejects.toMatchObject({ statusCode: 401 });
    expect(User.findOne).not.toHaveBeenCalled();
    expect(User.create).not.toHaveBeenCalled();
    expect(sessions).toHaveLength(0);
  });
});

describe('sessions: refresh and logout', () => {
  const login = async (u) => {
    jest.spyOn(User, 'findOne').mockResolvedValue(u);
    return authService.verifyOtp({ email, otp: '123456' });
  };

  test('refresh works while the session exists and keeps the same session id', async () => {
    const u = dbUser();
    const { refreshToken } = await login(u);
    jest.spyOn(User, 'findById').mockResolvedValue(u);
    const next = await authService.refresh(refreshToken);
    expect(jwt.verify(next.accessToken, process.env.JWT_SECRET).sid).toBe(sessions[0].sid);
    expect(sessions).toHaveLength(1);
  });
  test('logout revokes the session: the refresh token stops working immediately', async () => {
    const u = dbUser();
    const { refreshToken } = await login(u);
    jest.spyOn(User, 'findById').mockResolvedValue(u);
    await expect(authService.logout(refreshToken)).resolves.toEqual({ loggedOut: true });
    expect(sessions).toHaveLength(0);
    await expect(authService.refresh(refreshToken)).rejects.toMatchObject({ statusCode: 401 });
  });
  test('logout is idempotent and tolerates junk tokens', async () => {
    await expect(authService.logout('junk')).resolves.toEqual({ loggedOut: true });
    await expect(authService.logout(undefined)).resolves.toEqual({ loggedOut: true });
  });
  test('logout of one device leaves other sessions alone; logout-all clears every session', async () => {
    const u = dbUser();
    const a = await login(u);
    await login(u);
    expect(sessions).toHaveLength(2);
    await authService.logout(a.refreshToken);
    expect(sessions).toHaveLength(1);
    await authService.logoutAll(u._id);
    expect(sessions).toHaveLength(0);
  });
  test('legacy refresh tokens without a session id are rejected', async () => {
    const legacy = jwt.sign({ id: 'x', role: 'customer' }, process.env.JWT_REFRESH_SECRET);
    await expect(authService.refresh(legacy)).rejects.toMatchObject({ statusCode: 401 });
  });
  test('refresh for a deactivated user fails', async () => {
    const u = dbUser();
    const { refreshToken } = await login(u);
    jest.spyOn(User, 'findById').mockResolvedValue({ ...u, isActive: false });
    await expect(authService.refresh(refreshToken)).rejects.toMatchObject({ statusCode: 401 });
  });
});

describe('password login still works', () => {
  const q = (u) => ({ select: async () => u });
  test('deactivated -> 403, wrong password -> 401, right password -> tokens + session', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    jest.spyOn(User, 'findOne').mockReturnValue(q(dbUser({ passwordHash, isActive: false })));
    await expect(authService.login({ email, password: 'password123' })).rejects.toMatchObject({ statusCode: 403 });
    jest.spyOn(User, 'findOne').mockReturnValue(q(dbUser({ passwordHash })));
    await expect(authService.login({ email, password: 'nope' })).rejects.toMatchObject({ statusCode: 401 });
    const ok = await authService.login({ email, password: 'password123' });
    expect(ok.accessToken && ok.refreshToken).toBeTruthy();
    expect(sessions).toHaveLength(1);
    expect(JSON.stringify(ok)).not.toMatch(/passwordHash/);
  });
  test('unknown user -> same 401 as wrong password', async () => {
    jest.spyOn(User, 'findOne').mockReturnValue(q(null));
    await expect(authService.login({ email, password: 'x' })).rejects.toMatchObject({ statusCode: 401, message: 'Invalid credentials' });
  });
});
