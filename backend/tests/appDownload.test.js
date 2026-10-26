// The QR is verified by DECODING the PNG the API returns and comparing it with the configured URL.
const request = require('supertest');
const mongoose = require('mongoose');
const { PNG } = require('pngjs');
const jsQR = require('jsqr');
const svc = require('../src/services/appDownload.service');
const logger = require('../src/utils/logger');

mongoose.set('bufferCommands', false);
const app = require('../src/app');

const binary = (res, cb) => { const c = []; res.on('data', (d) => c.push(d)); res.on('end', () => cb(null, Buffer.concat(c))); };
const decode = (buf) => {
  const png = PNG.sync.read(buf);
  return jsQR(new Uint8ClampedArray(png.data), png.width, png.height)?.data ?? null;
};

beforeEach(() => {
  jest.spyOn(logger, 'warn').mockImplementation(() => {});
  for (const k of svc.SOURCES) delete process.env[k];
});
afterEach(() => jest.restoreAllMocks());

test('unconfigured: info says so, QR endpoint is 404 — nothing is invented', async () => {
  const info = await request(app).get('/api/v1/app/download');
  expect(info.body.data).toEqual({ configured: false });
  const qr = await request(app).get('/api/v1/app/download-qr.png');
  expect(qr.status).toBe(404); expect(qr.body.error.code).toBe('DOWNLOAD_NOT_CONFIGURED');
});

test('configured URL: PNG decodes back to exactly that URL', async () => {
  process.env.APP_WEB_URL = 'https://app.example.org/install?src=qr&x=1';
  const info = await request(app).get('/api/v1/app/download');
  expect(info.body.data).toMatchObject({ configured: true, url: 'https://app.example.org/install?src=qr&x=1', platform: 'web' });
  const res = await request(app).get('/api/v1/app/download-qr.png').buffer().parse(binary);
  expect(res.status).toBe(200); expect(res.headers['content-type']).toBe('image/png');
  expect(decode(res.body)).toBe('https://app.example.org/install?src=qr&x=1');
});

test('store links are labelled as "as configured", never as verified-live', () => {
  process.env.APP_ANDROID_URL = 'https://play.google.com/store/apps/details?id=org.example.app';
  const i = svc.getDownloadInfo();
  expect(i).toMatchObject({ platform: 'android', source: 'APP_ANDROID_URL' });
  expect(i.label).toMatch(/as configured/);
  delete process.env.APP_ANDROID_URL; process.env.APP_IOS_URL = 'https://apps.apple.com/in/app/example/id123';
  expect(svc.getDownloadInfo().platform).toBe('ios');
});

test('APP_DOWNLOAD_URL takes precedence over the others', () => {
  process.env.APP_WEB_URL = 'https://web.example.org/'; process.env.APP_DOWNLOAD_URL = 'https://dl.example.org/';
  expect(svc.getDownloadInfo().url).toBe('https://dl.example.org/');
});

test.each([
  ['http://app.example.org/', 'https'],
  ['https://localhost:3000/', 'public'],
  ['https://127.0.0.1/', 'public'],
  ['https://192.168.1.5/app', 'public'],
  ['https://10.0.0.7/', 'public'],
  ['https://172.20.1.1/', 'public'],
  ['https://[::1]/', 'public'],
  ['https://intranet/', 'public'],
  ['https://printer.local/', 'public'],
  ['https://user:pw@app.example.org/', 'credentials'],
  ['javascript:alert(1)', 'https'],
  ['not a url', 'valid'],
  ['ftp://x.example.org/', 'https'],
])('rejects unsafe destination %s', async (bad, why) => {
  process.env.APP_DOWNLOAD_URL = bad;
  const info = svc.getDownloadInfo();
  expect(info.configured).toBe(false); expect(info.problem).toContain(why);
  expect((await request(app).get('/api/v1/app/download-qr.png')).status).toBe(404);
});

test('an invalid higher-priority value does not silently fall back to another URL', () => {
  process.env.APP_DOWNLOAD_URL = 'http://bad.example.org/'; process.env.APP_WEB_URL = 'https://ok.example.org/';
  expect(svc.getDownloadInfo().configured).toBe(false);
});

test('the public info response never echoes problems or env names', async () => {
  process.env.APP_DOWNLOAD_URL = 'https://localhost/';
  expect(JSON.stringify((await request(app).get('/api/v1/app/download')).body)).not.toMatch(/APP_|localhost/);
});
