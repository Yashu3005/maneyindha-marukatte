// OTP lifecycle against the real otp.service / email.service code. Only the two I/O edges are
// replaced: MongoDB (in-memory stand-in) and the Resend SDK client (recording stand-in).
const { installMemoryModel, fakeResendClient, codeFromEmail } = require('./fakes/memoryModel');
require('./helpers');
const OtpToken = require('../src/models/OtpToken');
const emailService = require('../src/services/email.service');
const otp = require('../src/services/otp.service');
const logger = require('../src/utils/logger');

const EMAIL = 'asha@example.com';
let rows; let resend; let logged;

beforeEach(() => {
  jest.useFakeTimers({ now: new Date('2026-10-26T12:00:00Z'), doNotFake: ['nextTick', 'setImmediate', 'queueMicrotask'] });
  jest.restoreAllMocks();
  rows = installMemoryModel(OtpToken, { attempts: 0, consumedAt: null });
  resend = fakeResendClient();
  emailService._setClient(resend);
  process.env.RESEND_API_KEY = 're_test_key_for_unit_tests';
  process.env.RESEND_FROM_EMAIL = 'Maneyindha Marukatte <login@mail.example.org>';
  logged = [];
  for (const level of ['info', 'warn', 'error', 'debug']) jest.spyOn(logger, level).mockImplementation((...a) => { logged.push(a.join(' ')); });
});
afterEach(() => jest.useRealTimers());

const advance = (ms) => jest.setSystemTime(new Date(Date.now() + ms));
const issue = async (email = EMAIL) => { await otp.requestOtp(email); return codeFromEmail(resend.sent[resend.sent.length - 1]); };

describe('requesting a code', () => {
  test('calls Resend once with the right sender, recipient and a 6-digit code', async () => {
    const res = await otp.requestOtp('  ASHA@Example.com ');
    expect(resend.emails.send).toHaveBeenCalledTimes(1);
    const msg = resend.sent[0];
    expect(msg.from).toBe('Maneyindha Marukatte <login@mail.example.org>');
    expect(msg.to).toEqual([EMAIL]); // normalized
    expect(msg.html).toMatch(/expires in 5 minutes/);
    expect(msg.text).toMatch(/\b\d{6}\b/);
    expect(res).toEqual({ sent: true, expiresInSeconds: 300, resendAfterSeconds: 60 });
  });
  test('the API result never contains the code, and the database stores only a keyed hash', async () => {
    const res = await otp.requestOtp(EMAIL);
    const code = codeFromEmail(resend.sent[0]);
    expect(JSON.stringify(res)).not.toContain(code);
    expect(JSON.stringify(rows)).not.toContain(code);
    expect(rows[0].codeHash).toMatch(/^[0-9a-f]{64}$/);
  });
  test('the code is never written to logs', async () => {
    const code = await issue();
    await otp.verifyOtp(EMAIL, code);
    expect(logged.join('\n')).not.toContain(code);
  });
  test('codes are random, not fixed', async () => {
    const seen = new Set();
    for (let i = 0; i < 6; i += 1) { advance(61000); seen.add(await issue()); }
    expect(seen.size).toBeGreaterThan(1);
    expect(seen.has('029403')).toBe(false);
  });
  test('resend cooldown: a second request within 60s is refused and sends nothing', async () => {
    await otp.requestOtp(EMAIL);
    await expect(otp.requestOtp(EMAIL)).rejects.toMatchObject({ statusCode: 429, code: 'OTP_COOLDOWN', retryAfterSeconds: 60 });
    advance(30000);
    await expect(otp.requestOtp(EMAIL)).rejects.toMatchObject({ retryAfterSeconds: 30 });
    expect(resend.emails.send).toHaveBeenCalledTimes(1);
    advance(31000);
    await expect(otp.requestOtp(EMAIL)).resolves.toMatchObject({ sent: true });
    expect(resend.emails.send).toHaveBeenCalledTimes(2);
  });
  test('cooldown is per address', async () => {
    await otp.requestOtp(EMAIL);
    await expect(otp.requestOtp('other@example.com')).resolves.toMatchObject({ sent: true });
  });
});

describe('verifying a code', () => {
  test('correct code verifies and returns the normalized email', async () => {
    const code = await issue();
    await expect(otp.verifyOtp('ASHA@example.com', code)).resolves.toBe(EMAIL);
  });
  test('wrong code -> 401 and the real code still works afterwards', async () => {
    const code = await issue();
    const wrong = code === '000000' ? '000001' : '000000';
    await expect(otp.verifyOtp(EMAIL, wrong)).rejects.toMatchObject({ statusCode: 401, code: 'OTP_INVALID' });
    await expect(otp.verifyOtp(EMAIL, code)).resolves.toBe(EMAIL);
  });
  test('5 wrong attempts lock the code — even the correct code is then refused (429)', async () => {
    const code = await issue();
    const wrong = code === '000000' ? '000001' : '000000';
    for (let i = 0; i < 5; i += 1) await expect(otp.verifyOtp(EMAIL, wrong)).rejects.toMatchObject({ statusCode: 401 });
    await expect(otp.verifyOtp(EMAIL, code)).rejects.toMatchObject({ statusCode: 429, code: 'OTP_LOCKED' });
  });
  test('expired code (5 min) is refused', async () => {
    const code = await issue();
    advance(5 * 60 * 1000 - 1000);
    await expect(otp.verifyOtp(EMAIL, code)).resolves.toBe(EMAIL); // still valid just before expiry
    const code2 = await (async () => { advance(61000); return issue(); })();
    advance(5 * 60 * 1000 + 1000);
    await expect(otp.verifyOtp(EMAIL, code2)).rejects.toMatchObject({ statusCode: 401 });
  });
  test('replay: a used code cannot be used again', async () => {
    const code = await issue();
    await otp.verifyOtp(EMAIL, code);
    await expect(otp.verifyOtp(EMAIL, code)).rejects.toMatchObject({ statusCode: 401 });
  });
  test('concurrent use of the same code: exactly one wins', async () => {
    const code = await issue();
    const results = await Promise.allSettled([otp.verifyOtp(EMAIL, code), otp.verifyOtp(EMAIL, code)]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
  });
  test('a newer code supersedes the older one', async () => {
    const first = await issue();
    advance(61000);
    const second = await issue();
    if (first !== second) await expect(otp.verifyOtp(EMAIL, first)).rejects.toMatchObject({ statusCode: 401 });
    await expect(otp.verifyOtp(EMAIL, second)).resolves.toBe(EMAIL);
    expect(rows).toHaveLength(1); // one live row per address
  });
  test('a code for one account cannot verify another', async () => {
    const code = await issue('a@example.com');
    await expect(otp.verifyOtp('b@example.com', code)).rejects.toMatchObject({ statusCode: 401 });
    await expect(otp.verifyOtp('a@example.com', code)).resolves.toBe('a@example.com');
  });
  test('the hash is bound to the purpose: a login code is not valid for another purpose', async () => {
    const code = await issue();
    await expect(otp.verifyOtp(EMAIL, code, 'password-reset')).rejects.toMatchObject({ statusCode: 401 });
  });
  test('no code outstanding -> 401 (same answer as a wrong code)', async () => {
    await expect(otp.verifyOtp('nobody@example.com', '123456')).rejects.toMatchObject({ statusCode: 401, message: 'Invalid or expired code' });
  });
});

describe('provider failures never leave a usable/verified state', () => {
  test.each([
    ['invalid_api_key', 502, 'EMAIL_SEND_FAILED'],
    ['rate_limit', 503, 'EMAIL_SEND_FAILED'],
    ['throw', 502, 'EMAIL_SEND_FAILED'],
  ])('Resend %s -> %i, row removed so the user can retry immediately', async (mode, status, code) => {
    resend.mode = mode;
    await expect(otp.requestOtp(EMAIL)).rejects.toMatchObject({ statusCode: status, code });
    expect(rows).toHaveLength(0);
    resend.mode = 'ok';
    await expect(otp.requestOtp(EMAIL)).resolves.toMatchObject({ sent: true }); // no cooldown burned
  });
  test('error messages never reveal the API key or provider internals', async () => {
    resend.mode = 'invalid_api_key';
    const err = await otp.requestOtp(EMAIL).catch((e) => e);
    expect(err.message).not.toMatch(/re_test|api key|invalid_api_key/i);
    expect(logged.join('\n')).not.toContain(process.env.RESEND_API_KEY);
    expect(logged.join('\n')).toMatch(/invalid_api_key/); // ops still sees the provider error name
  });
  test('missing configuration -> clear 503 without values', async () => {
    emailService._setClient(null);
    delete process.env.RESEND_API_KEY;
    const err = await otp.requestOtp(EMAIL).catch((e) => e);
    expect(err).toMatchObject({ statusCode: 503, code: 'EMAIL_NOT_CONFIGURED' });
    expect(rows).toHaveLength(0);
  });
  test('delivery status lookup goes through Resend (acceptance != delivery)', async () => {
    const status = await emailService.getDeliveryStatus('em_1');
    expect(resend.emails.get).toHaveBeenCalledWith('em_1');
    expect(status.lastEvent).toBe('delivered');
  });
});
