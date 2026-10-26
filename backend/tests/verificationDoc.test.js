process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const { v2: cloudinary } = require('cloudinary');
const Business = require('../src/models/Business');
const docs = require('../src/services/verificationDoc.service');
const logger = require('../src/utils/logger');
const { oid, bearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32)]);
const PDF = Buffer.concat([Buffer.from('%PDF-1.7\n'), Buffer.alloc(64, 2)]);

let ownerId; let bizId; let biz; let uploads; let destroyed;
const mk = (status = 'pending') => new Business({ owner: ownerId, name: 'Asha Bakes', verification: { status } });

beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(logger, 'error').mockImplementation(() => {});
  jest.spyOn(logger, 'warn').mockImplementation(() => {});
  process.env.CLOUDINARY_CLOUD_NAME = 'demo'; process.env.CLOUDINARY_API_KEY = 'k'; process.env.CLOUDINARY_API_SECRET = 's';
  ownerId = String(oid()); biz = mk(); bizId = String(biz._id); uploads = []; destroyed = [];
  jest.spyOn(Business, 'findOne').mockImplementation(async (q) => (String(q._id) === bizId && String(q.owner) === ownerId ? biz : null));
  jest.spyOn(Business, 'findById').mockImplementation(async (id) => (String(id) === bizId ? biz : null));
  jest.spyOn(Business.prototype, 'save').mockResolvedValue(undefined);
  jest.spyOn(docs._provider, 'upload').mockImplementation(async (buf, o) => { uploads.push({ buf, ...o }); return { public_id: `verification/${o.publicId}` }; });
  jest.spyOn(docs._provider, 'destroy').mockImplementation(async (d) => { destroyed.push(d.publicId); return {}; });
  jest.spyOn(docs._provider, 'signedUrl').mockImplementation((d) => `https://api.cloudinary.com/signed/${d.publicId}?expires=soon`);
});

const up = (buf, fields = { type: 'business_proof' }, role = 'entrepreneur', name = 'doc.pdf', id = bizId) => {
  let r = request(app).post(`${api}/businesses/${id}/documents`).set(bearer(role, ownerId));
  for (const [k, v] of Object.entries(fields)) r = r.field(k, v);
  return r.attach('file', buf, { filename: name });
};
const ID = { type: 'id_proof', identityType: 'Aadhaar' };
const submit = (role = 'entrepreneur', body = {}) => request(app).post(`${api}/businesses/${bizId}/verification-documents`).set(bearer(role, ownerId)).send(body);

describe('upload', () => {
  test('accepts PDF, JPEG and PNG by content; stores them privately with no public URL', async () => {
    expect((await up(PDF, { type: 'business_proof' })).status).toBe(200);
    expect((await up(JPEG, ID, 'entrepreneur', 'id.jpg')).status).toBe(200);
    const res = await up(PNG, { type: 'address_proof' }, 'entrepreneur', 'a.png');
    expect(res.status).toBe(200);
    expect(uploads.map((u) => u.kind)).toEqual(['raw', 'image', 'image']);
    const stored = biz.verification.documents;
    expect(stored).toHaveLength(3);
    for (const d of stored) { expect(d.url).toBeUndefined(); expect(d.publicId).toMatch(/^verification\/[0-9a-f]{24}_/); }
    // the response never leaks storage ids
    expect(JSON.stringify(res.body)).not.toContain('publicId');
    expect(JSON.stringify(res.body)).not.toContain(stored[0].publicId);
  });

  test('identityType is stored only for ID proofs', async () => {
    await up(PDF, { type: 'business_proof', identityType: 'Aadhaar' });
    await up(JPEG, ID);
    const byType = Object.fromEntries(biz.verification.documents.map((d) => [d.type, d.identityType]));
    expect(byType).toEqual({ business_proof: undefined, id_proof: 'Aadhaar' });
  });

  test('the real provider uploads as authenticated (private) assets, never public, in the right resource type', async () => {
    jest.restoreAllMocks();
    const calls = [];
    jest.spyOn(cloudinary.uploader, 'upload_stream').mockImplementation((opts, cb) => {
      calls.push(opts);
      return { end: () => cb(null, { public_id: `${opts.folder}/${opts.public_id}` }) };
    });
    await docs._provider.upload(PDF, { publicId: 'abc', kind: 'raw' });
    await docs._provider.upload(JPEG, { publicId: 'def', kind: 'image' });
    expect(calls.map((c) => c.type)).toEqual(['authenticated', 'authenticated']);
    expect(calls.map((c) => c.resource_type)).toEqual(['raw', 'image']);
    expect(calls.every((c) => c.folder === 'verification')).toBe(true);
  });

  test('type is decided by content, not by the declared name', async () => {
    for (const bad of [Buffer.from('<?php echo 1;'), Buffer.from('<svg onload=alert(1)>'), Buffer.from('GIF89a....'), Buffer.from('MZ\x90\x00exe')]) {
      expect((await up(bad, { type: 'business_proof' }, 'entrepreneur', 'x.pdf')).status).toBe(415);
    }
    expect(uploads).toHaveLength(0);
  });

  test('over 5 MB -> 413 and never reaches the provider; exactly 5 MB is accepted', async () => {
    expect((await up(Buffer.concat([PDF, Buffer.alloc(5 * 1024 * 1024)]))).status).toBe(413);
    expect(uploads).toHaveLength(0);
    expect((await up(Buffer.concat([PDF, Buffer.alloc(5 * 1024 * 1024 - PDF.length)]))).status).toBe(200);
  });

  test('field validation: missing/invalid type, id_proof needs an identity type, missing file', async () => {
    expect((await up(PDF, {})).status).toBe(422);
    expect((await up(PDF, { type: 'selfie' })).status).toBe(422);
    expect((await up(PDF, { type: 'id_proof' })).status).toBe(422);
    expect((await up(PDF, { type: 'id_proof', identityType: 'Library card' })).status).toBe(422);
    const noFile = await request(app).post(`${api}/businesses/${bizId}/documents`).set(bearer('entrepreneur', ownerId)).field('type', 'business_proof');
    expect(noFile.status).toBe(422);
    expect(uploads).toHaveLength(0);
  });

  test('authorization: anonymous 401, customer 403; another owner gets 404 and nothing is uploaded', async () => {
    expect((await request(app).post(`${api}/businesses/${bizId}/documents`).field('type', 'business_proof').attach('file', PDF, 'a.pdf')).status).toBe(401);
    expect((await up(PDF, { type: 'business_proof' }, 'customer')).status).toBe(403);
    const stranger = String(oid());
    const res = await request(app).post(`${api}/businesses/${bizId}/documents`).set(bearer('entrepreneur', stranger)).field('type', 'business_proof').attach('file', PDF, 'a.pdf');
    expect(res.status).toBe(404);
    expect(uploads).toHaveLength(0);
  });

  test('a re-upload replaces the previous document of the same type and removes the old remote file', async () => {
    await up(PDF, { type: 'business_proof' });
    const first = biz.verification.documents[0].publicId;
    await new Promise((r) => setTimeout(r, 3));
    await up(JPEG, { type: 'business_proof' }, 'entrepreneur', 'b.jpg');
    expect(biz.verification.documents).toHaveLength(1);
    expect(biz.verification.documents[0].publicId).not.toBe(first);
    expect(destroyed).toEqual([first]);
  });

  test('locked while under review or approved', async () => {
    for (const st of ['in_review', 'approved']) {
      biz = mk(st); bizId = String(biz._id);
      expect((await up(PDF, { type: 'business_proof' })).status).toBe(422);
    }
    expect(uploads).toHaveLength(0);
  });

  test('a rejected application can upload again', async () => {
    biz = mk('rejected'); bizId = String(biz._id);
    expect((await up(PDF, { type: 'business_proof' })).status).toBe(200);
  });

  test('503 when storage is not configured; 502 without internals when the provider fails', async () => {
    delete process.env.CLOUDINARY_API_SECRET;
    const a = await up(PDF); expect(a.status).toBe(503); expect(a.body.error.code).toBe('UPLOAD_NOT_CONFIGURED');
    process.env.CLOUDINARY_API_SECRET = 's';
    docs._provider.upload.mockRejectedValueOnce(new Error('cloud says: api_secret=XYZ'));
    const b = await up(PDF); expect(b.status).toBe(502); expect(JSON.stringify(b.body)).not.toContain('XYZ');
    expect(biz.verification.documents).toHaveLength(0);
  });

  test('the original file name is sanitised', async () => {
    await up(PDF, { type: 'business_proof' }, 'entrepreneur', '../../etc/<script>.pdf');
    expect(biz.verification.documents[0].originalName).not.toMatch(/[\\/<>]/);
  });
});

describe('list and remove', () => {
  test('owner sees metadata only; can remove a document while editable', async () => {
    await up(PDF, { type: 'business_proof' });
    const list = await request(app).get(`${api}/businesses/${bizId}/documents`).set(bearer('entrepreneur', ownerId));
    expect(list.status).toBe(200);
    expect(list.body.data.documents).toHaveLength(1);
    expect(JSON.stringify(list.body)).not.toContain(biz.verification.documents[0].publicId);
    const id = list.body.data.documents[0].id;
    const del = await request(app).delete(`${api}/businesses/${bizId}/documents/${id}`).set(bearer('entrepreneur', ownerId));
    expect(del.status).toBe(200);
    expect(biz.verification.documents).toHaveLength(0);
    expect(destroyed).toHaveLength(1);
    expect((await request(app).delete(`${api}/businesses/${bizId}/documents/${oid()}`).set(bearer('entrepreneur', ownerId))).status).toBe(404);
  });
  test('cannot remove once in review', async () => {
    await up(PDF, { type: 'business_proof' });
    const id = String(biz.verification.documents[0]._id);
    biz.verification.status = 'in_review';
    expect((await request(app).delete(`${api}/businesses/${bizId}/documents/${id}`).set(bearer('entrepreneur', ownerId))).status).toBe(422);
  });
});

describe('submit', () => {
  test('refused until BOTH required documents were really uploaded', async () => {
    expect((await submit()).status).toBe(422);
    await up(PDF, { type: 'business_proof' });
    const one = await submit(); expect(one.status).toBe(422); expect(one.body.error.code).toBe('DOCUMENTS_MISSING');
    expect(biz.verification.status).toBe('pending');
    await up(JPEG, ID);
    const ok = await submit();
    expect(ok.status).toBe(200);
    expect(ok.body.data.status).toBe('in_review');
    expect(biz.verification.status).toBe('in_review');
  });
  test('URLs in the body cannot stand in for uploads (the old hole)', async () => {
    const res = await submit('entrepreneur', { documents: [{ type: 'id_proof', url: 'https://evil.example/x.png' }, { type: 'business_proof', url: 'https://evil.example/y.png' }] });
    expect(res.status).toBe(422);
    expect(biz.verification.documents).toHaveLength(0);
    expect(biz.verification.status).toBe('pending');
  });
  test('cannot be submitted twice or after approval; customers cannot submit', async () => {
    await up(PDF, { type: 'business_proof' }); await up(JPEG, ID);
    expect((await submit()).status).toBe(200);
    expect((await submit()).status).toBe(422);
    expect((await submit('customer')).status).toBe(403);
  });
});

describe('admin link', () => {
  const link = (role, docId) => request(app).get(`${api}/admin/verifications/${bizId}/documents/${docId}/link`).set(bearer(role));
  test('admin gets a short-lived signed link; nobody else does', async () => {
    await up(PDF, { type: 'business_proof' });
    const docId = String(biz.verification.documents[0]._id);
    const res = await link('admin', docId);
    expect(res.status).toBe(200);
    expect(res.body.data.url).toMatch(/^https:\/\//);
    expect(res.body.data.expiresInSeconds).toBe(300);
    expect(res.headers['cache-control']).toBe('no-store');
    expect((await link('entrepreneur', docId)).status).toBe(403);
    expect((await link('customer', docId)).status).toBe(403);
    expect((await request(app).get(`${api}/admin/verifications/${bizId}/documents/${docId}/link`)).status).toBe(401);
    expect((await link('admin', String(oid()))).status).toBe(404);
  });
});
