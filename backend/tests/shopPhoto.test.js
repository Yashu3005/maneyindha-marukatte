// Shop cover photos: upload, removal, public "coverUrl", and the rule for which picture represents a shop.
process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const Business = require('../src/models/Business');
const svc = require('../src/services/shopPhoto.service');
const logger = require('../src/utils/logger');
const { coverOf } = require('../src/utils/shopPhoto');
const { oid, bearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);

let ownerId; let biz; let bizId; let uploads; let destroyed;
beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(logger, 'error').mockImplementation(() => {});
  jest.spyOn(logger, 'warn').mockImplementation(() => {});
  process.env.CLOUDINARY_CLOUD_NAME = 'demo'; process.env.CLOUDINARY_API_KEY = 'k'; process.env.CLOUDINARY_API_SECRET = 's';
  ownerId = String(oid()); biz = new Business({ owner: ownerId, name: 'Asha Bakes' }); bizId = String(biz._id);
  uploads = []; destroyed = [];
  jest.spyOn(Business, 'findOne').mockImplementation(async (q) => (String(q._id) === bizId && String(q.owner) === ownerId ? biz : null));
  jest.spyOn(Business.prototype, 'save').mockResolvedValue(undefined);
  jest.spyOn(svc._provider, 'upload').mockImplementation(async (buf, pid) => { uploads.push(pid); return { secure_url: `https://res.cloudinary.com/demo/image/upload/v1/shops/${pid}.jpg` }; });
  jest.spyOn(svc._provider, 'destroy').mockImplementation(async (pid) => { destroyed.push(pid); return {}; });
});
const post = (buf = JPEG, who = ownerId, role = 'entrepreneur') =>
  request(app).post(`${api}/businesses/${bizId}/photo`).set(bearer(role, who)).attach('photo', buf, { filename: 'shop.jpg', contentType: 'image/jpeg' });

describe('upload', () => {
  test('owner uploads a cover; it is stored in bannerUrl with one stable id per shop', async () => {
    const res = await post();
    expect(res.status).toBe(200);
    expect(res.body.data.bannerUrl).toMatch(/^https:\/\/res\.cloudinary\.com\//);
    expect(biz.bannerUrl).toBe(res.body.data.bannerUrl);
    expect(uploads).toEqual([`shop_${bizId}`]);
  });
  test('only the owner: another entrepreneur gets 404, a customer 403, signed-out 401', async () => {
    expect((await post(JPEG, String(oid()))).status).toBe(404);
    expect((await post(JPEG, ownerId, 'customer')).status).toBe(403);
    expect((await request(app).post(`${api}/businesses/${bizId}/photo`)).status).toBe(401);
    expect(uploads).toHaveLength(0);
  });
  test('type by content, 3 MB cap, and missing config are all refused before/without hitting the host', async () => {
    expect((await post(Buffer.from('<svg onload=alert(1)>'))).status).toBe(415);
    expect((await post(Buffer.concat([JPEG, Buffer.alloc(3 * 1024 * 1024)]))).status).toBe(413);
    delete process.env.CLOUDINARY_API_SECRET;
    expect((await post()).status).toBe(503);
    expect(uploads).toHaveLength(0);
  });
  test('a failing host is a 502 and the shop keeps its old photo', async () => {
    biz.bannerUrl = 'https://res.cloudinary.com/demo/image/upload/old.jpg';
    svc._provider.upload.mockRejectedValueOnce({ http_code: 500, message: 'boom' });
    expect((await post()).status).toBe(502);
    expect(biz.bannerUrl).toContain('old.jpg');
  });
  test('remove clears the cover and deletes the stored file', async () => {
    biz.bannerUrl = 'https://res.cloudinary.com/demo/image/upload/old.jpg';
    const res = await request(app).delete(`${api}/businesses/${bizId}/photo`).set(bearer('entrepreneur', ownerId));
    expect(res.body.data).toEqual({ removed: true });
    expect(biz.bannerUrl).toBeUndefined();
    expect(destroyed).toEqual([`shop_${bizId}`]);
  });
});

describe('which picture represents a shop', () => {
  test('cover, then logo, then first gallery photo; only real https URLs; never invented', () => {
    expect(coverOf({ bannerUrl: 'https://x/c.jpg', logoUrl: 'https://x/l.jpg' })).toBe('https://x/c.jpg');
    expect(coverOf({ logoUrl: 'https://x/l.jpg' })).toBe('https://x/l.jpg');
    expect(coverOf({ gallery: ['https://x/g1.jpg'] })).toBe('https://x/g1.jpg');
    expect(coverOf({ bannerUrl: 'http://insecure/c.jpg', logoUrl: 'javascript:alert(1)', gallery: ['not a url'] })).toBeUndefined();
    expect(coverOf({})).toBeUndefined();
    expect(coverOf(undefined)).toBeUndefined();
  });
  test('the public shop list carries coverUrl and no private fields', async () => {
    const chain = { select: () => chain, sort: () => chain, skip: () => chain, limit: () => chain, populate: async () => [
      { toObject: () => ({ _id: oid(), name: 'A', bannerUrl: 'https://res.cloudinary.com/demo/a.jpg' }) },
      { toObject: () => ({ _id: oid(), name: 'B' }) },
    ] };
    jest.spyOn(Business, 'find').mockReturnValue(chain);
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(2);
    const res = await request(app).get(`${api}/businesses`);
    expect(res.status).toBe(200);
    expect(res.body.data[0].coverUrl).toBe('https://res.cloudinary.com/demo/a.jpg');
    expect(res.body.data[1].coverUrl).toBeUndefined();
  });
});
