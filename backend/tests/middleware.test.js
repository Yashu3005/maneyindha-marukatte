const express = require('express');
const request = require('supertest');
const { tokenFor } = require('./helpers');
const { errorHandler } = require('../src/middleware/error');
const { requireAuth, optionalAuth } = require('../src/middleware/auth');
const { assertEnv } = require('../src/config/env');
const { parsePage } = require('../src/utils/pagination');
const { slugify } = require('../src/utils/slug');

function appThrowing(err) {
  const a = express();
  a.get('/', (_req, _res, next) => next(err));
  a.use(errorHandler);
  return a;
}

describe('errorHandler maps library errors to proper statuses', () => {
  test.each([
    [{ name: 'CastError', path: '_id' }, 400, 'Invalid _id'],
    [{ name: 'ValidationError', errors: { a: { message: 'a is required' } } }, 422, 'a is required'],
    [{ code: 11000 }, 409, 'Duplicate value'],
    [{ type: 'entity.too.large' }, 413, 'Request body too large'],
  ])('%j', async (err, status, message) => {
    const res = await request(appThrowing(Object.assign(new Error('boom internal detail'), err))).get('/');
    expect(res.status).toBe(status);
    expect(res.body.error.message).toBe(message);
    expect(JSON.stringify(res.body)).not.toMatch(/boom internal detail|stack/);
  });
  test('unknown errors -> generic 500', async () => {
    const res = await request(appThrowing(new Error('secret path /etc/passwd'))).get('/');
    expect(res.status).toBe(500);
    expect(res.body.error.message).toBe('Internal server error');
  });
  test('operational AppError keeps its status and message', async () => {
    const AppError = require('../src/utils/AppError');
    const res = await request(appThrowing(new AppError('nope', 418))).get('/');
    expect(res.status).toBe(418);
    expect(res.body.error.message).toBe('nope');
  });
});

describe('optionalAuth', () => {
  const a = express();
  a.get('/', optionalAuth, (req, res) => res.json({ user: req.user ? req.user.role : null }));
  a.get('/strict', requireAuth, (req, res) => res.json({ user: req.user.role }));
  test('anonymous / bad token -> anonymous (not an error)', async () => {
    expect((await request(a).get('/')).body.user).toBeNull();
    expect((await request(a).get('/').set('Authorization', 'Bearer junk')).body.user).toBeNull();
  });
  test('valid token -> user attached', async () => {
    expect((await request(a).get('/').set('Authorization', `Bearer ${tokenFor('entrepreneur')}`)).body.user).toBe('entrepreneur');
  });
});

describe('assertEnv', () => {
  const good = { MONGODB_URI: 'mongodb://x', JWT_SECRET: 'a'.repeat(40), JWT_REFRESH_SECRET: 'b'.repeat(40) };
  test('passes with required vars', () => expect(() => assertEnv(good)).not.toThrow());
  test('names every missing var', () => {
    expect(() => assertEnv({})).toThrow(/MONGODB_URI, JWT_SECRET, JWT_REFRESH_SECRET/);
  });
  test('production rejects placeholder / short / identical secrets', () => {
    expect(() => assertEnv({ ...good, NODE_ENV: 'production', JWT_SECRET: 'replace-with-long-random-string-xxxxxxxxxxxxx' })).toThrow(/Weak/);
    expect(() => assertEnv({ ...good, NODE_ENV: 'production', JWT_SECRET: 'short' })).toThrow(/Weak/);
    expect(() => assertEnv({ ...good, NODE_ENV: 'production', JWT_REFRESH_SECRET: good.JWT_SECRET })).toThrow(/differ/);
    expect(() => assertEnv({ ...good, NODE_ENV: 'production' })).not.toThrow();
  });
  test('short secrets are fine outside production (tests/dev)', () => {
    expect(() => assertEnv({ ...good, JWT_SECRET: 'x', JWT_REFRESH_SECRET: 'y' })).not.toThrow();
  });
});

describe('helpers', () => {
  test('parsePage clamps hostile values', () => {
    expect(parsePage({ page: '-5', limit: '100000' })).toEqual({ page: 1, limit: 50, skip: 0 });
    expect(parsePage({ page: '3', limit: '10' })).toEqual({ page: 3, limit: 10, skip: 20 });
    expect(parsePage({ page: 'abc', limit: 'x' })).toEqual({ page: 1, limit: 20, skip: 0 });
  });
  test('slugify never collapses non-latin names into the same "-" slug', () => {
    expect(slugify("Asha's Home Bakes")).toBe('asha-s-home-bakes');
    const a = slugify('ಬೇಕರಿ');
    const b = slugify('ಕರಕುಶಲ');
    expect(a).not.toBe('-');
    expect(a).not.toBe(b);
    expect(slugify('ಬೇಕರಿ')).toBe(a); // stable
  });
});
