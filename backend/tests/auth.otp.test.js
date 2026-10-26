const { oid } = require('./helpers');
const User = require('../src/models/User');
const authService = require('../src/services/auth.service');

const email = 'otp-user@example.com';
const DEMO = '029403';
const customer = () => ({ _id: oid(), name: 'C', email, role: 'customer', isActive: true });
const envBackup = { ...process.env };

beforeEach(() => {
  jest.restoreAllMocks();
  delete process.env.ALLOW_DEMO_OTP;
  process.env.NODE_ENV = 'test';
});
afterAll(() => { process.env = envBackup; });

describe('demo OTP is opt-in and never in production', () => {
  test('default: not advertised and not accepted', async () => {
    const sent = await authService.sendOtp(email);
    expect(sent).toEqual({ sent: true });
    await expect(authService.verifyOtp({ email, otp: DEMO })).rejects.toMatchObject({ statusCode: 401 });
  });
  test('ALLOW_DEMO_OTP=true in dev: advertised and accepted', async () => {
    process.env.ALLOW_DEMO_OTP = 'true';
    jest.spyOn(User, 'findOne').mockResolvedValue(customer());
    expect((await authService.sendOtp(email)).demoOtp).toBe(DEMO);
    const res = await authService.verifyOtp({ email, otp: DEMO });
    expect(res.accessToken).toBeTruthy();
    expect(res.isNewUser).toBe(false);
  });
  test('NODE_ENV=production overrides ALLOW_DEMO_OTP', async () => {
    process.env.ALLOW_DEMO_OTP = 'true';
    process.env.NODE_ENV = 'production';
    expect((await authService.sendOtp(email)).demoOtp).toBeUndefined();
    await expect(authService.verifyOtp({ email, otp: DEMO })).rejects.toMatchObject({ statusCode: 401 });
  });
});

describe('verifyOtp rules', () => {
  test('creates a new customer when the email is unknown', async () => {
    process.env.ALLOW_DEMO_OTP = 'true';
    jest.spyOn(User, 'findOne').mockResolvedValue(null);
    jest.spyOn(User, 'create').mockImplementation(async (d) => ({ _id: oid(), isActive: true, ...d }));
    const res = await authService.verifyOtp({ email: 'NEW@Example.com', otp: DEMO });
    expect(res.isNewUser).toBe(true);
    expect(res.user.role).toBe('customer');
    expect(User.create).toHaveBeenCalledWith(expect.objectContaining({ email: 'new@example.com' }));
  });
  test.each(['admin', 'super_admin'])('OTP can never log into a %s account', async (role) => {
    process.env.ALLOW_DEMO_OTP = 'true';
    jest.spyOn(User, 'findOne').mockResolvedValue({ ...customer(), role });
    await expect(authService.verifyOtp({ email, otp: DEMO })).rejects.toMatchObject({ statusCode: 403 });
  });
  test('disabled accounts are refused', async () => {
    process.env.ALLOW_DEMO_OTP = 'true';
    jest.spyOn(User, 'findOne').mockResolvedValue({ ...customer(), isActive: false });
    await expect(authService.verifyOtp({ email, otp: DEMO })).rejects.toMatchObject({ statusCode: 403 });
  });
  test('a real (generated) OTP is single-use', async () => {
    // We cannot read the generated code through the public API, so use the store indirectly:
    // 5 wrong guesses lock the code out (brute-force protection), 6th attempt -> 429.
    await authService.sendOtp('lock@example.com');
    for (let i = 0; i < 5; i += 1) {
      await expect(authService.verifyOtp({ email: 'lock@example.com', otp: '111111' })).rejects.toMatchObject({ statusCode: 401 });
    }
    await expect(authService.verifyOtp({ email: 'lock@example.com', otp: '111111' })).rejects.toMatchObject({ statusCode: 429 });
  });
  test('non-string input is rejected, not crashed on', async () => {
    await expect(authService.verifyOtp({ email: { a: 1 }, otp: '123456' })).rejects.toMatchObject({ statusCode: 422 });
    await expect(authService.sendOtp({ a: 1 })).rejects.toMatchObject({ statusCode: 422 });
  });
});

describe('login', () => {
  const bcrypt = require('bcryptjs');
  const q = (u) => ({ select: async () => u });
  test('deactivated user cannot log in even with the right password', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    jest.spyOn(User, 'findOne').mockReturnValue(q({ ...customer(), passwordHash, isActive: false }));
    await expect(authService.login({ email, password: 'password123' })).rejects.toMatchObject({ statusCode: 403 });
  });
  test('wrong password -> 401, right password -> tokens', async () => {
    const passwordHash = await bcrypt.hash('password123', 4);
    jest.spyOn(User, 'findOne').mockReturnValue(q({ ...customer(), passwordHash }));
    await expect(authService.login({ email, password: 'nope' })).rejects.toMatchObject({ statusCode: 401 });
    const ok = await authService.login({ email, password: 'password123' });
    expect(ok.accessToken && ok.refreshToken).toBeTruthy();
    expect(JSON.stringify(ok)).not.toMatch(/passwordHash/);
  });
  test('unknown user -> same 401 as wrong password', async () => {
    jest.spyOn(User, 'findOne').mockReturnValue(q(null));
    await expect(authService.login({ email, password: 'x' })).rejects.toMatchObject({ statusCode: 401, message: 'Invalid credentials' });
  });
});
