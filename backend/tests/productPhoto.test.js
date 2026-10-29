process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const svc = require('../src/services/productPhoto.service');
const logger = require('../src/utils/logger');
const { oid, bearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const url = '/api/v1/products/photo';
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);

let id; let uploads;
beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(logger, 'error').mockImplementation(() => {});
  process.env.CLOUDINARY_CLOUD_NAME = 'demo'; process.env.CLOUDINARY_API_KEY = 'k'; process.env.CLOUDINARY_API_SECRET = 's';
  id = String(oid()); uploads = [];
  jest.spyOn(svc._provider, 'upload').mockImplementation(async (buf, pid) => { uploads.push(pid); return { secure_url: `https://res.cloudinary.com/demo/image/upload/products/${pid}.jpg` }; });
});
const post = (buf, role = 'entrepreneur', name = 'p.jpg') =>
  request(app).post(url).set(bearer(role, id)).attach('photo', buf, { filename: name, contentType: 'image/jpeg' });

test('entrepreneur uploads a valid photo and gets an https URL', async () => {
  const res = await post(JPEG);
  expect(res.status).toBe(200);
  expect(res.body.data.url).toMatch(/^https:\/\/res\.cloudinary\.com\//);
  expect(uploads).toHaveLength(1);
});
test('customers cannot upload product photos', async () => {
  expect((await post(JPEG, 'customer')).status).toBe(403);
  expect(uploads).toHaveLength(0);
});
test('type decided by content; over 3 MB rejected; nothing reaches the provider', async () => {
  expect((await post(Buffer.from('<svg onload=alert(1)>'))).status).toBe(415);
  expect((await post(Buffer.concat([JPEG, Buffer.alloc(3 * 1024 * 1024)]))).status).toBe(413);
  expect(uploads).toHaveLength(0);
});
test('not configured gives 503', async () => {
  delete process.env.CLOUDINARY_API_SECRET;
  expect((await post(JPEG)).status).toBe(503);
});
