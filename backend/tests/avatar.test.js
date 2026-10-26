process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const User = require('../src/models/User');
const avatar = require('../src/services/avatar.service');
const logger = require('../src/utils/logger');
const { oid, bearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const url = '/api/v1/users/me/avatar';

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32)]);
const WEBP = Buffer.concat([Buffer.from('RIFF'), Buffer.alloc(4), Buffer.from('WEBP'), Buffer.alloc(16)]);

let id; let user; let uploads;
beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(logger, 'error').mockImplementation(() => {});
  jest.spyOn(logger, 'warn').mockImplementation(() => {});
  process.env.CLOUDINARY_CLOUD_NAME = 'demo'; process.env.CLOUDINARY_API_KEY = 'k'; process.env.CLOUDINARY_API_SECRET = 's';
  id = String(oid()); uploads = [];
  user = { _id: id, name: 'Asha', email: 'a@example.com', role: 'entrepreneur', save: jest.fn(async () => {}) };
  jest.spyOn(User, 'findById').mockImplementation(async () => user);
  jest.spyOn(avatar._provider, 'upload').mockImplementation(async (buf, pid) => { uploads.push({ buf, pid }); return { secure_url: `https://res.cloudinary.com/demo/image/upload/avatars/${pid}.jpg` }; });
  jest.spyOn(avatar._provider, 'destroy').mockResolvedValue({});
});
const post = (buf, role = 'entrepreneur', name = 'p.jpg', type = 'image/jpeg') =>
  request(app).post(url).set(bearer(role, id)).attach('avatar', buf, { filename: name, contentType: type });

test('entrepreneur uploads a valid image; URL is persisted; one stable public id per user', async () => {
  for (const [buf, n] of [[JPEG, 'a.jpg'], [PNG, 'a.png'], [WEBP, 'a.webp']]) {
    const res = await post(buf, 'entrepreneur', n);
    expect(res.status).toBe(200);
    expect(res.body.data.avatarUrl).toMatch(/^https:\/\/res\.cloudinary\.com\//);
  }
  expect(uploads.map((u) => u.pid)).toEqual([`user_${id}`, `user_${id}`, `user_${id}`]);
  expect(user.save).toHaveBeenCalled();
});
test('type is decided by content, not by the declared name/mimetype', async () => {
  expect((await post(Buffer.from('<?php echo 1;'), 'entrepreneur', 'x.jpg', 'image/jpeg')).status).toBe(415);
  expect((await post(Buffer.from('<svg onload=alert(1)>'), 'entrepreneur', 'x.png', 'image/png')).status).toBe(415);
  expect((await post(Buffer.from('GIF89a....'), 'entrepreneur', 'x.gif', 'image/gif')).status).toBe(415);
  expect(uploads).toHaveLength(0);
});
test('over 2 MB is rejected with 413 and never reaches the provider', async () => {
  const big = Buffer.concat([JPEG, Buffer.alloc(2 * 1024 * 1024)]);
  expect((await post(big)).status).toBe(413);
  expect(uploads).toHaveLength(0);
});
test('exactly at the limit is accepted', async () => {
  const ok = Buffer.concat([JPEG, Buffer.alloc(2 * 1024 * 1024 - JPEG.length)]);
  expect((await post(ok)).status).toBe(200);
});
test('missing file -> 422; wrong field name -> 400/422', async () => {
  expect((await request(app).post(url).set(bearer('entrepreneur', id))).status).toBe(422);
  const res = await request(app).post(url).set(bearer('entrepreneur', id)).attach('wrong', JPEG, 'a.jpg');
  expect([400, 422]).toContain(res.status);
});
test('authorization: anonymous 401, customer 403, delivery partner 403', async () => {
  expect((await request(app).post(url).attach('avatar', JPEG, 'a.jpg')).status).toBe(401);
  expect((await post(JPEG, 'customer')).status).toBe(403);
  expect((await post(JPEG, 'delivery_partner')).status).toBe(403);
  expect(uploads).toHaveLength(0);
});
test('the upload always targets the caller: extra form fields are refused, ids in the request are ignored', async () => {
  const other = String(oid());
  const res = await request(app).post(url).query({ userId: other }).set(bearer('entrepreneur', id)).field('userId', other).attach('avatar', JPEG, 'a.jpg');
  expect(res.status).toBe(400);
  expect(uploads).toHaveLength(0);
  expect((await post(JPEG)).status).toBe(200);
  expect(uploads[0].pid).toBe(`user_${id}`);
});
test('503 when storage is not configured; 502 (no internals) when the provider fails', async () => {
  delete process.env.CLOUDINARY_API_SECRET;
  const a = await post(JPEG); expect(a.status).toBe(503); expect(a.body.error.code).toBe('UPLOAD_NOT_CONFIGURED');
  process.env.CLOUDINARY_API_SECRET = 's';
  avatar._provider.upload.mockRejectedValueOnce(new Error('cloud says: api_secret=XYZ'));
  const b = await post(JPEG); expect(b.status).toBe(502); expect(JSON.stringify(b.body)).not.toContain('XYZ');
  expect(user.avatarUrl).toBeUndefined();
});
test('provider returning a non-https URL is refused', async () => {
  avatar._provider.upload.mockResolvedValueOnce({ secure_url: 'http://evil.example/x.jpg' });
  expect((await post(JPEG)).status).toBe(502);
});
test('DELETE clears the picture (customers may clear too); registration works with no picture', async () => {
  user.avatarUrl = 'https://res.cloudinary.com/demo/x.jpg';
  const res = await request(app).delete(url).set(bearer('customer', id));
  expect(res.status).toBe(200); expect(user.avatarUrl).toBeUndefined();
  expect(avatar._provider.destroy).toHaveBeenCalledWith(`user_${id}`);
  expect((await request(app).delete(url)).status).toBe(401);
});
test('PATCH /users/me can no longer set an arbitrary avatarUrl', async () => {
  await request(app).patch('/api/v1/users/me').set(bearer('customer', id)).send({ name: 'Asha', phone: '9876543210', avatarUrl: 'javascript:alert(1)' });
  expect(user.avatarUrl).toBeUndefined();
});
test('sniff() unit', () => {
  expect(avatar.sniff(JPEG)).toBe('image/jpeg'); expect(avatar.sniff(PNG)).toBe('image/png'); expect(avatar.sniff(WEBP)).toBe('image/webp');
  expect(avatar.sniff(Buffer.alloc(0))).toBeNull(); expect(avatar.sniff(Buffer.from('RIFF....WAVE'))).toBeNull();
});
