// Brevo provider with a stubbed fetch (no network). A real Brevo call has NOT been made from this environment.
const emailService = require('../src/services/email.service');
const { emailConfigIssues } = require('../src/config/env');
const logger = require('../src/utils/logger');

const KEY = 'xkeysib-test-not-real-0123456789';
let fetchMock; let logs;
beforeEach(() => {
  jest.restoreAllMocks();
  logs = [];
  for (const l of ['info', 'warn', 'error']) jest.spyOn(logger, l).mockImplementation((...a) => { logs.push(a.join(' ')); });
  process.env.EMAIL_PROVIDER = 'brevo'; process.env.BREVO_API_KEY = KEY;
  process.env.BREVO_FROM_EMAIL = 'Maneyindha <me@example.org>';
  fetchMock = jest.fn(async () => ({ ok: true, status: 201, json: async () => ({ messageId: '<abc@smtp-relay.brevo.com>' }) }));
  global.fetch = fetchMock;
});
afterEach(() => { delete process.env.EMAIL_PROVIDER; });

test('sends via Brevo REST with api-key header, parsed sender, code in html and text', async () => {
  const r = await emailService.sendOtpEmail({ to: 'a@b.com', code: '123456', expiresMinutes: 5 });
  expect(r.id).toBe('<abc@smtp-relay.brevo.com>');
  const [url, init] = fetchMock.mock.calls[0];
  expect(url).toBe('https://api.brevo.com/v3/smtp/email');
  expect(init.headers['api-key']).toBe(KEY);
  const body = JSON.parse(init.body);
  expect(body.sender).toEqual({ name: 'Maneyindha', email: 'me@example.org' });
  expect(body.to).toEqual([{ email: 'a@b.com' }]);
  expect(body.htmlContent).toContain('123456'); expect(body.textContent).toContain('123456');
  expect(init.signal).toBeInstanceOf(AbortSignal);
});
test('logs the message id but never the key, code or recipient', async () => {
  await emailService.sendOtpEmail({ to: 'private@b.com', code: '654321', expiresMinutes: 5 });
  const all = logs.join('\n');
  expect(all).toMatch(/accepted by Brevo/);
  for (const secret of [KEY, '654321', 'private@b.com']) expect(all).not.toContain(secret);
});
test('provider rejection -> 502 EMAIL_SEND_FAILED, no leak; 429 -> 503; network/timeout -> 502', async () => {
  fetchMock.mockResolvedValueOnce({ ok: false, status: 401, json: async () => ({ code: 'unauthorized', message: `bad key ${KEY}` }) });
  await expect(emailService.sendOtpEmail({ to: 'a@b.com', code: '1', expiresMinutes: 5 })).rejects.toMatchObject({ statusCode: 502, code: 'EMAIL_SEND_FAILED' });
  expect(logs.join('\n')).not.toContain(KEY);
  fetchMock.mockResolvedValueOnce({ ok: false, status: 429, json: async () => ({}) });
  await expect(emailService.sendOtpEmail({ to: 'a@b.com', code: '1', expiresMinutes: 5 })).rejects.toMatchObject({ statusCode: 503 });
  fetchMock.mockRejectedValueOnce(Object.assign(new Error('t'), { name: 'TimeoutError' }));
  await expect(emailService.sendOtpEmail({ to: 'a@b.com', code: '1', expiresMinutes: 5 })).rejects.toMatchObject({ statusCode: 502 });
  fetchMock.mockResolvedValueOnce({ ok: true, status: 201, json: async () => ({}) }); // 2xx but no id is not "accepted"
  await expect(emailService.sendOtpEmail({ to: 'a@b.com', code: '1', expiresMinutes: 5 })).rejects.toMatchObject({ statusCode: 502 });
});
test('unconfigured -> 503 and no request is made', async () => {
  delete process.env.BREVO_API_KEY;
  await expect(emailService.sendOtpEmail({ to: 'a@b.com', code: '1', expiresMinutes: 5 })).rejects.toMatchObject({ statusCode: 503, code: 'EMAIL_NOT_CONFIGURED' });
  expect(fetchMock).not.toHaveBeenCalled();
});
test('config checks follow the selected provider; unknown provider is reported', () => {
  expect(emailConfigIssues({ EMAIL_PROVIDER: 'brevo', BREVO_API_KEY: KEY, BREVO_FROM_EMAIL: 'N <me@gmail.com>' })).toEqual([]);
  expect(emailConfigIssues({ EMAIL_PROVIDER: 'brevo' }).length).toBe(2);
  expect(emailConfigIssues({ EMAIL_PROVIDER: 'brevo', BREVO_API_KEY: KEY, BREVO_FROM_EMAIL: 'nope' })[0]).toMatch(/valid address/);
  expect(emailConfigIssues({ EMAIL_PROVIDER: 'smtp' })[0]).toMatch(/not supported/);
  // default stays Resend with its own rules
  expect(emailConfigIssues({ RESEND_API_KEY: 're_abcdefghijkl', RESEND_FROM_EMAIL: 'a@gmail.com' })[0]).toMatch(/cannot send from/);
});
test('delivery lookup is Resend-only and says so', async () => {
  await expect(emailService.getDeliveryStatus('x')).rejects.toMatchObject({ code: 'EMAIL_STATUS_UNSUPPORTED' });
});
test('parseFrom handles name+address, bare address and junk', () => {
  expect(emailService.parseFrom('"A B" <a@b.co>')).toEqual({ name: 'A B', email: 'a@b.co' });
  expect(emailService.parseFrom('a@b.co')).toEqual({ name: undefined, email: 'a@b.co' });
  expect(emailService.parseFrom('')).toBeNull();
});
