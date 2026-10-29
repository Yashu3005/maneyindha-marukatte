// Shop promo ("story") videos: signed direct upload, server-side checking, public shape, takedown.
process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const { v2: cloudinary } = require('cloudinary');
const Business = require('../src/models/Business');
const User = require('../src/models/User');
const promo = require('../src/services/promoVideo.service');
const logger = require('../src/utils/logger');
const { oid, bearer, installAdmin, adminBearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';

let ownerId; let biz; let bizId; let destroyed; let remote;
const mk = (status = 'approved') => new Business({ owner: ownerId, name: 'Asha Bakes', verification: { status } });
const pid = (suffix = 'a'.repeat(24)) => `promo/${bizId}/${suffix}`;
const GOOD_INFO = { format: 'mp4', bytes: 8 * 1024 * 1024, duration: 32.4 };

beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(logger, 'error').mockImplementation(() => {});
  jest.spyOn(logger, 'warn').mockImplementation(() => {});
  process.env.CLOUDINARY_CLOUD_NAME = 'demo'; process.env.CLOUDINARY_API_KEY = 'key123'; process.env.CLOUDINARY_API_SECRET = 'shh-secret';
  ownerId = String(oid()); biz = mk(); bizId = String(biz._id); destroyed = []; remote = { ...GOOD_INFO };
  jest.spyOn(Business, 'findOne').mockImplementation(async (q) => (String(q._id) === bizId && String(q.owner) === ownerId ? biz : null));
  jest.spyOn(Business, 'findById').mockImplementation(async (id) => (String(id) === bizId ? biz : null));
  jest.spyOn(Business.prototype, 'save').mockResolvedValue(undefined);
  jest.spyOn(promo._provider, 'resource').mockImplementation(async () => remote);
  jest.spyOn(promo._provider, 'destroy').mockImplementation(async (id) => { destroyed.push(id); return {}; });
  jest.spyOn(promo._provider, 'urls').mockImplementation((id) => ({ url: `https://res.cloudinary.com/demo/video/upload/${id}.mp4`, posterUrl: `https://res.cloudinary.com/demo/video/upload/${id}.jpg` }));
});

const sign = (role = 'entrepreneur') => request(app).post(`${api}/businesses/${bizId}/promo-video/signature`).set(bearer(role, ownerId));
const attach = (body, role = 'entrepreneur') => request(app).post(`${api}/businesses/${bizId}/promo-video`).set(bearer(role, ownerId)).send(body);

describe('signature', () => {
  test('returns a signature that Cloudinary would accept, scoped to this shop, without the secret', async () => {
    const res = await sign();
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    const { uploadUrl, fields, publicId, limits } = res.body.data;
    expect(uploadUrl).toBe('https://api.cloudinary.com/v1_1/demo/video/upload');
    expect(publicId).toMatch(new RegExp(`^promo/${bizId}/[a-f0-9]{24}$`));
    expect(fields).toMatchObject({ public_id: publicId, api_key: 'key123', allowed_formats: 'mp4,mov,webm' });
    expect(Math.abs(fields.timestamp - Date.now() / 1000)).toBeLessThan(5);
    // recompute the signature exactly as Cloudinary does: sorted params + secret
    const signed = { ...fields }; const { signature } = fields;
    delete signed.signature; delete signed.api_key;
    expect(signature).toBe(cloudinary.utils.api_sign_request(signed, 'shh-secret'));
    expect(limits).toEqual({ maxBytes: 40 * 1024 * 1024, maxSeconds: 60, formats: ['mp4', 'mov', 'webm'] });
    expect(JSON.stringify(res.body)).not.toContain('shh-secret');
  });
  test('a new public id each time', async () => {
    const a = (await sign()).body.data.publicId; const b = (await sign()).body.data.publicId;
    expect(a).not.toBe(b);
  });
  test.each(['pending', 'in_review', 'rejected'])('refused while the shop is %s', async (status) => {
    biz = mk(status);
    const res = await sign();
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('BUSINESS_NOT_APPROVED');
  });
  test('only the owner entrepreneur; others look like "not found"', async () => {
    expect((await sign('customer')).status).toBe(403);
    expect((await request(app).post(`${api}/businesses/${bizId}/promo-video/signature`).set(bearer('entrepreneur', String(oid())))).status).toBe(404);
    expect((await request(app).post(`${api}/businesses/${bizId}/promo-video/signature`)).status).toBe(401);
  });
  test('503 when uploads are not configured', async () => {
    delete process.env.CLOUDINARY_API_SECRET;
    const res = await sign();
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('UPLOAD_NOT_CONFIGURED');
  });
});

describe('attach (the server checks what was uploaded)', () => {
  test('accepts a valid video, stores derived https URLs and hides the storage id publicly', async () => {
    const res = await attach({ publicId: pid(), title: ' Making of our cakes ', caption: 'Baked fresh every morning' });
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({
      url: `https://res.cloudinary.com/demo/video/upload/${pid()}.mp4`, posterUrl: expect.stringMatching(/\.jpg$/),
      duration: 32.4, title: 'Making of our cakes', caption: 'Baked fresh every morning', status: 'pending', reason: undefined,
    });
    expect(biz.promoVideo.publicId).toBe(pid());
    expect(biz.promoVideo.bytes).toBe(GOOD_INFO.bytes);
    expect(JSON.stringify(res.body)).not.toContain('publicId');
    expect(promo._provider.resource).toHaveBeenCalledWith(pid());
  });
  test.each([
    ['too long', { duration: 61.2 }, /60 seconds/],
    ['too big', { bytes: 40 * 1024 * 1024 + 1 }, /40 MB/],
    ['wrong format', { format: 'avi' }, /MP4, MOV or WebM/],
    ['empty', { bytes: 0 }, /40 MB/],
    ['no duration', { duration: 0 }, /60 seconds/],
  ])('rejects a video that is %s and deletes the upload', async (_n, patch, msg) => {
    remote = { ...GOOD_INFO, ...patch };
    const res = await attach({ publicId: pid() });
    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('VIDEO_INVALID');
    expect(res.body.error.message).toMatch(msg);
    expect(destroyed).toEqual([pid()]);
    expect(biz.promoVideo?.url).toBeUndefined();
  });
  test('boundary values are accepted: exactly 60 s and exactly 40 MB', async () => {
    remote = { format: 'webm', bytes: 40 * 1024 * 1024, duration: 60 };
    expect((await attach({ publicId: pid() })).status).toBe(200);
  });
  test('a public id from another shop or another folder is refused before Cloudinary is asked', async () => {
    for (const bad of [`promo/${oid()}/${'a'.repeat(24)}`, `verification/${bizId}/${'a'.repeat(24)}`, `promo/${bizId}/../x`, `promo/${bizId}/short`, '']) {
      expect((await attach({ publicId: bad })).status).toBe(bad === '' ? 422 : 422);
    }
    expect(promo._provider.resource).not.toHaveBeenCalled();
  });
  test('unknown upload -> 422 UPLOAD_NOT_FOUND; Cloudinary outage -> 502', async () => {
    promo._provider.resource.mockRejectedValueOnce({ http_code: 404 });
    expect((await attach({ publicId: pid() })).body.error.code).toBe('UPLOAD_NOT_FOUND');
    promo._provider.resource.mockRejectedValueOnce({ http_code: 500, message: 'boom' });
    const res = await attach({ publicId: pid() });
    expect(res.status).toBe(502);
    expect(res.body.error.code).toBe('UPLOAD_FAILED');
  });
  test('replacing a video deletes the old file; re-attaching the same one does not', async () => {
    await attach({ publicId: pid('b'.repeat(24)) });
    await attach({ publicId: pid('c'.repeat(24)) });
    expect(destroyed).toEqual([pid('b'.repeat(24))]);
    destroyed.length = 0;
    await attach({ publicId: pid('c'.repeat(24)) });
    expect(destroyed).toEqual([]);
  });
  test('refused for an unapproved shop and for non-owners; title/caption are validated', async () => {
    biz = mk('pending');
    expect((await attach({ publicId: pid() })).status).toBe(403);
    biz = mk();
    expect((await attach({ publicId: pid() }, 'customer')).status).toBe(403);
    expect((await attach({ publicId: pid(), title: 'x'.repeat(81) })).status).toBe(422);
    expect((await attach({ publicId: pid(), caption: 'x'.repeat(241) })).status).toBe(422);
    expect((await attach({})).status).toBe(422);
  });
});

describe('remove and takedown', () => {
  test('owner removes their video and the remote file is deleted', async () => {
    await attach({ publicId: pid() });
    const res = await request(app).delete(`${api}/businesses/${bizId}/promo-video`).set(bearer('entrepreneur', ownerId));
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({ removed: true });
    expect(biz.promoVideo?.publicId).toBeUndefined();
    expect(biz.promoVideo?.url).toBeUndefined();
    expect(destroyed).toContain(pid());
  });
  test('removing when there is none is harmless', async () => {
    const res = await request(app).delete(`${api}/businesses/${bizId}/promo-video`).set(bearer('entrepreneur', ownerId));
    expect(res.body.data).toEqual({ removed: false });
  });
  test('only the admin can take down any shop\'s video; owners and customers cannot use that route', async () => {
    await attach({ publicId: pid() });
    const url = `${api}/admin/businesses/${bizId}/promo-video`;
    expect((await request(app).delete(url).set(bearer('entrepreneur', ownerId))).status).toBe(403);
    expect((await request(app).delete(url).set(bearer('customer'))).status).toBe(403);
    installAdmin(User);
    const res = await request(app).delete(url).set(adminBearer());
    expect(res.status).toBe(200);
    expect(biz.promoVideo?.publicId).toBeUndefined();
    expect(biz.promoVideo?.url).toBeUndefined();
    expect(destroyed).toContain(pid());
  });
});

describe('public shape', () => {
  test('GET /businesses/:id for a customer shows the video without storage ids; the owner sees their own record', async () => {
    biz.promoVideo = { publicId: pid(), url: 'https://res.cloudinary.com/demo/video/upload/x.mp4', posterUrl: 'https://res.cloudinary.com/demo/video/upload/x.jpg', duration: 20, bytes: 1234, format: 'mp4', title: 'Hello', review: { status: 'approved' } };
    jest.spyOn(Business, 'findById').mockReturnValue({ populate: async () => biz });
    const pub = await request(app).get(`${api}/businesses/${bizId}`).set(bearer('customer'));
    expect(pub.status).toBe(200);
    expect(pub.body.data.promoVideo).toEqual({ url: expect.any(String), posterUrl: expect.any(String), duration: 20, title: 'Hello', caption: undefined });
    expect(JSON.stringify(pub.body)).not.toContain(pid());
    expect(JSON.stringify(pub.body)).not.toContain('1234');
  });
});

describe('admin review and home ads', () => {
  const reviewUrl = () => `${api}/admin/businesses/${bizId}/promo-video/review`;
  test('a new video starts pending and is hidden from customers until approved', async () => {
    await attach({ publicId: pid() });
    expect(biz.promoVideo.review.status).toBe('pending');
    jest.spyOn(Business, 'findById').mockReturnValue({ populate: async () => biz });
    const hidden = await request(app).get(`${api}/businesses/${bizId}`).set(bearer('customer'));
    expect(hidden.body.data.promoVideo).toBeUndefined();
    biz.promoVideo.review = { status: 'approved' };
    const shown = await request(app).get(`${api}/businesses/${bizId}`).set(bearer('customer'));
    expect(shown.body.data.promoVideo.url).toMatch(/^https:/);
  });
  test('only the admin can review; approve goes live, reject needs a reason', async () => {
    await attach({ publicId: pid() });
    expect((await request(app).post(reviewUrl()).set(bearer('entrepreneur', ownerId)).send({ action: 'approve' })).status).toBe(403);
    installAdmin(User);
    expect((await request(app).post(reviewUrl()).set(adminBearer()).send({ action: 'reject' })).status).toBe(422);
    expect(biz.promoVideo.review.status).toBe('pending');
    const rej = await request(app).post(reviewUrl()).set(adminBearer()).send({ action: 'reject', reason: 'Please film in better light' });
    expect(rej.status).toBe(200);
    expect(biz.promoVideo.review).toMatchObject({ status: 'rejected', reason: 'Please film in better light' });
    expect((await request(app).post(reviewUrl()).set(adminBearer()).send({ action: 'approve' })).body.data.status).toBe('approved');
    expect(biz.promoVideo.review.status).toBe('approved');
  });
  test('the admin queue lists pending videos (legacy ones without a status included)', async () => {
    biz.promoVideo = { publicId: pid(), url: 'https://res.cloudinary.com/demo/video/upload/x.mp4', posterUrl: 'https://res.cloudinary.com/demo/video/upload/x.jpg', duration: 9 };
    const chain = { select: () => chain, sort: () => chain, limit: () => chain, lean: async () => [{ _id: biz._id, name: biz.name, promoVideo: biz.promoVideo }] };
    const find = jest.spyOn(Business, 'find').mockReturnValue(chain);
    installAdmin(User);
    const res = await request(app).get(`${api}/admin/promo-videos`).set(adminBearer());
    expect(res.status).toBe(200);
    expect(res.body.data[0]).toMatchObject({ name: 'Asha Bakes', promoVideo: { status: 'pending' } });
    expect(JSON.stringify(find.mock.calls[0][0])).toContain('pending');
    expect((await request(app).get(`${api}/admin/promo-videos`).set(bearer('customer'))).status).toBe(403);
  });
  test('home ads: public, at most the asked count, only approved videos from approved shops, never cached', async () => {
    const agg = jest.spyOn(Business, 'aggregate').mockResolvedValue([
      { _id: biz._id, name: 'Asha Bakes', rating: { avg: 4.5, count: 3 }, promoVideo: { url: 'https://res.cloudinary.com/demo/video/upload/x.mp4', posterUrl: 'https://res.cloudinary.com/demo/video/upload/x.jpg', title: 'Hi', duration: 12 } },
    ]);
    const res = await request(app).get(`${api}/businesses/promo-ads?limit=4`);
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toMatch(/no-store/);
    expect(res.body.data[0]).toMatchObject({ businessId: String(biz._id), name: 'Asha Bakes', video: { url: expect.stringMatching(/^https:/) } });
    const pipeline = agg.mock.calls[0][0];
    expect(JSON.stringify(pipeline[0])).toContain('"promoVideo.review.status":"approved"');
    expect(JSON.stringify(pipeline[0])).toContain('"verification.status":"approved"');
    expect(pipeline[1]).toEqual({ $sample: { size: 4 } });
    await request(app).get(`${api}/businesses/promo-ads?limit=99`);
    expect(agg.mock.calls[1][0][1]).toEqual({ $sample: { size: 8 } });
  });
});
