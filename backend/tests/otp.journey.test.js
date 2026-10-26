// The full sign-in journey through the real Express app over HTTP:
//   email -> POST /auth/otp/send -> (Resend) -> POST /auth/otp/verify -> session -> protected
//   endpoint -> logout -> refresh refused.
// Edges stubbed: MongoDB models (in-memory) and the Resend client. Everything else is real.
// Trust X-Forwarded-For so each test can present as a different client (the per-IP limiter is real).
process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const { installMemoryModel, fakeResendClient, codeFromEmail } = require('./fakes/memoryModel');
const { oid } = require('./helpers');
const OtpToken = require('../src/models/OtpToken');
const RefreshSession = require('../src/models/RefreshSession');
const User = require('../src/models/User');
const emailService = require('../src/services/email.service');
const logger = require('../src/utils/logger');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';

let resend; let sessions; let users;
beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(logger, 'error').mockImplementation(() => {});
  installMemoryModel(OtpToken, { attempts: 0, consumedAt: null });
  sessions = installMemoryModel(RefreshSession);
  users = [];
  jest.spyOn(User, 'findOne').mockImplementation(async (q) => users.find((u) => u.email === q.email) || null);
  jest.spyOn(User, 'findById').mockImplementation(async (id) => users.find((u) => String(u._id) === String(id)) || null);
  jest.spyOn(User, 'create').mockImplementation(async (d) => { const u = { _id: oid(), isActive: true, save: async () => {}, ...d }; users.push(u); return u; });
  resend = fakeResendClient();
  emailService._setClient(resend);
  process.env.RESEND_API_KEY = 're_test_key_for_unit_tests';
  process.env.RESEND_FROM_EMAIL = 'MM <login@mail.example.org>';
});

let ipCounter = 0;
let currentIp = '10.0.0.1';
beforeEach(() => { ipCounter += 1; currentIp = `10.0.${Math.floor(ipCounter / 250)}.${(ipCounter % 250) + 1}`; });
const send = (email) => request(app).post(`${api}/auth/otp/send`).set('X-Forwarded-For', currentIp).send({ email });
const verify = (email, otp) => request(app).post(`${api}/auth/otp/verify`).set('X-Forwarded-For', currentIp).send({ email, otp });

test('happy path: new user signs in with an emailed code and uses the session', async () => {
  const sent = await send('Asha@Example.com');
  expect(sent.status).toBe(200);
  expect(sent.body.data).toEqual({ sent: true, expiresInSeconds: 300, resendAfterSeconds: 60 });
  expect(resend.sent).toHaveLength(1);
  expect(resend.sent[0].to).toEqual(['asha@example.com']);
  const code = codeFromEmail(resend.sent[0]);
  expect(JSON.stringify(sent.body)).not.toContain(code);

  const ok = await verify('asha@example.com', code);
  expect(ok.status).toBe(200);
  expect(ok.body.data).toMatchObject({ isNewUser: true, user: { email: 'asha@example.com', role: 'customer', emailVerified: true } });
  expect(users[0].emailVerified).toBe(true);
  const { accessToken, refreshToken } = ok.body.data;

  // The access token opens a protected endpoint; without it the same endpoint is 401.
  jest.spyOn(RefreshSession, 'deleteMany');
  expect((await request(app).post(`${api}/auth/logout-all`)).status).toBe(401);
  expect((await request(app).post(`${api}/auth/logout-all`).set('Authorization', `Bearer ${accessToken}`)).status).toBe(200);
  expect(sessions).toHaveLength(0);
  expect(refreshToken).toBeTruthy();
});

test('logout invalidates the session: refresh no longer works', async () => {
  await send('a@example.com');
  const { body } = await verify('a@example.com', codeFromEmail(resend.sent[0]));
  const { refreshToken } = body.data;
  expect((await request(app).post(`${api}/auth/refresh`).send({ refreshToken })).status).toBe(200);
  expect((await request(app).post(`${api}/auth/logout`).send({ refreshToken })).status).toBe(200);
  expect((await request(app).post(`${api}/auth/refresh`).send({ refreshToken })).status).toBe(401);
});

test('wrong code -> 401; reuse of a good code -> 401', async () => {
  await send('a@example.com');
  const code = codeFromEmail(resend.sent[0]);
  const wrong = code === '000000' ? '111111' : '000000';
  expect((await verify('a@example.com', wrong)).status).toBe(401);
  expect((await verify('a@example.com', code)).status).toBe(200);
  expect((await verify('a@example.com', code)).status).toBe(401);
});

test('the response for a known and an unknown email is identical (no account enumeration)', async () => {
  users.push({ _id: oid(), email: 'known@example.com', role: 'customer', isActive: true, emailVerified: true });
  const known = await send('known@example.com');
  const unknown = await send('unknown@example.com');
  expect(known.status).toBe(unknown.status);
  expect(known.body).toEqual(unknown.body);
});

test('resend cooldown over HTTP: 429 + Retry-After, only one email sent', async () => {
  await send('a@example.com');
  const again = await send('a@example.com');
  expect(again.status).toBe(429);
  expect(again.headers['retry-after']).toBe('60');
  expect(again.body.error).toMatchObject({ code: 'OTP_COOLDOWN', retryAfterSeconds: 60 });
  expect(resend.sent).toHaveLength(1);
});

test('lockout after 5 wrong codes over HTTP', async () => {
  await send('a@example.com');
  const code = codeFromEmail(resend.sent[0]);
  const wrong = code === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i += 1) expect((await verify('a@example.com', wrong)).status).toBe(401);
  const locked = await verify('a@example.com', code);
  expect(locked.status).toBe(429);
  expect(locked.body.error.code).toBe('OTP_LOCKED');
});

test('per-IP rate limit on sending: the 11th request in an hour is refused before any email work', async () => {
  for (let i = 0; i < 10; i += 1) {
    const r = await send(`user${i}@example.com`);
    expect(r.status).toBe(200);
  }
  const blocked = await send('user11@example.com');
  expect(blocked.status).toBe(429);
  expect(blocked.body.error.code).toBe('RATE_LIMITED');
  expect(resend.sent).toHaveLength(10);
});

test('input validation: bad email / bad code shapes never reach Resend or the DB', async () => {
  for (const email of ['', 'not-an-email', 'a@', { $ne: 1 }, 'x'.repeat(300) + '@example.com']) {
    expect((await send(email)).status).toBe(422); // 5 of the 10 allowed per IP
  }
  for (const otp of ['12345', '1234567', 'abcdef', '12 456', 123456, null, { $gt: '' }]) {
    expect((await verify('a@example.com', otp)).status).toBe(422);
  }
  expect(resend.emails.send).not.toHaveBeenCalled();
});

describe('provider failures are reported honestly', () => {
  test.each([['invalid_api_key', 502], ['throw', 502], ['rate_limit', 503]])('Resend %s -> %i and the user is NOT signed in', async (mode, status) => {
    resend.mode = mode;
    const res = await send('a@example.com');
    expect(res.status).toBe(status);
    expect(res.body.error.code).toBe('EMAIL_SEND_FAILED');
    expect(res.body.data).toBeUndefined();
    expect(JSON.stringify(res.body)).not.toMatch(/re_test|api key/i);
    expect(users).toHaveLength(0);
    expect(sessions).toHaveLength(0);
  });
  test('email not configured -> 503 EMAIL_NOT_CONFIGURED', async () => {
    emailService._setClient(null);
    delete process.env.RESEND_API_KEY;
    const res = await send('a@example.com');
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('EMAIL_NOT_CONFIGURED');
  });
});

test('there is no demo/bypass code: the old fixed OTP is just a wrong code', async () => {
  await send('a@example.com');
  const code = codeFromEmail(resend.sent[0]);
  if (code !== '029403') expect((await verify('a@example.com', '029403')).status).toBe(401);
  expect(users).toHaveLength(0);
});

test('logs carry the Resend message id but never the code or the email address', async () => {
  const lines = [];
  for (const level of ['info', 'warn', 'error', 'debug']) jest.spyOn(logger, level).mockImplementation((...a) => { lines.push(a.join(' ')); });
  const email = 'private.person@example.com';
  await send(email);
  const code = codeFromEmail(resend.sent[0]);
  await verify(email, '000000');
  await verify(email, code);
  const all = lines.join('\n');
  expect(all).not.toContain(code);
  expect(all).not.toContain(email);
  expect(all).not.toContain('private.person');
  expect(all).toMatch(/OTP email accepted by Resend \(id=/);
});
