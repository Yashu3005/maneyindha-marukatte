process.env.TRUST_PROXY = '1';
const request = require('supertest');
const mongoose = require('mongoose');
const Business = require('../src/models/Business');
const User = require('../src/models/User');
const geo = require('../src/utils/geo');
const { oid, bearer } = require('./helpers');

mongoose.set('bufferCommands', false);
const app = require('../src/app');
const api = '/api/v1';

afterEach(() => jest.restoreAllMocks());

describe('geo helpers', () => {
  test('isValidLatLng: ranges, non-finite, null island', () => {
    expect(geo.isValidLatLng(12.97, 77.59)).toBe(true);
    for (const [a, b] of [[91, 0], [-91, 0], [0, 181], [0, -181], [NaN, 1], [1, Infinity], ['12', '77'], [null, null], [0, 0]]) {
      expect(geo.isValidLatLng(a, b)).toBe(false);
    }
    expect(geo.isValidLatLng(0, 10)).toBe(true); // a real equator point is fine
  });
  test('coarsen rounds to ~110 m and keeps [lng, lat] order', () => {
    expect(geo.coarsen([77.594612, 12.971634])).toEqual([77.595, 12.972]);
  });
  test('haversine: known distances', () => {
    expect(geo.haversineKm(12.9716, 77.5946, 12.9716, 77.5946)).toBeCloseTo(0, 5);
    // Bengaluru -> Mysuru is ~126 km great-circle
    expect(geo.haversineKm(12.9716, 77.5946, 12.2958, 76.6394)).toBeGreaterThan(120);
    expect(geo.haversineKm(12.9716, 77.5946, 12.2958, 76.6394)).toBeLessThan(135);
    // 1 degree of latitude ≈ 111.2 km
    expect(geo.haversineKm(0, 0, 1, 0)).toBeCloseTo(111.19, 1);
  });
});

describe('Business model derives the public point', () => {
  test('exact stays exact, public is coarsened; no location -> none, valid without it', () => {
    const b = new Business({ owner: oid(), name: 'Shop', location: { coordinates: [77.594612, 12.971634] } });
    expect(b.validateSync()).toBeUndefined();
    // run the pre-validate hook
    return b.validate().then(() => {
      expect(b.location.coordinates).toEqual([77.594612, 12.971634]);
      expect(b.publicLocation.coordinates).toEqual([77.595, 12.972]);
      const none = new Business({ owner: oid(), name: 'Shop' });
      expect(none.validateSync()).toBeUndefined();
      expect(none.location?.coordinates).toBeUndefined();
      expect(none.locationSource).toBe('unset');
    });
  });
  test('model rejects out-of-range and (0,0) coordinates even if validation upstream is bypassed', () => {
    for (const c of [[181, 10], [10, 91], [0, 0], [1]]) {
      expect(new Business({ owner: oid(), name: 'S', location: { coordinates: c } }).validateSync()).toBeDefined();
    }
  });
});

describe('PATCH /businesses/:id/location', () => {
  const owner = String(oid()); const bid = String(oid());
  let biz;
  beforeEach(() => {
    biz = new Business({ _id: bid, owner, name: 'Shop' });
    biz.save = jest.fn(async function save() { await this.validate(); return this; });
    jest.spyOn(Business, 'findOne').mockImplementation(async (q) => (String(q.owner) === owner && String(q._id) === bid ? biz : null));
  });
  const patch = (body, who = bearer('entrepreneur', owner)) => request(app).patch(`${api}/businesses/${bid}/location`).set(who).send(body);

  test('owner sets a device location; exact + coarse stored; source recorded', async () => {
    const res = await patch({ lat: 12.971634, lng: 77.594612, source: 'device' });
    expect(res.status).toBe(200);
    expect(biz.location.coordinates).toEqual([77.594612, 12.971634]);
    expect(biz.publicLocation.coordinates).toEqual([77.595, 12.972]);
    expect(biz.locationSource).toBe('device');
  });
  test('invalid coordinates are rejected with 422 and nothing is saved', async () => {
    for (const body of [{ lat: 91, lng: 0, source: 'manual' }, { lat: 0, lng: 181, source: 'manual' }, { lat: 'x', lng: 1, source: 'manual' },
      { lat: 0, lng: 0, source: 'manual' }, { lat: 10, lng: 10 }, { lat: 10, lng: 10, source: 'gps-trust-me' }, {}]) {
      expect((await patch(body)).status).toBe(422);
    }
    expect(biz.save).not.toHaveBeenCalled();
  });
  test('only the owner: someone else gets 404, customer 403, anonymous 401', async () => {
    expect((await patch({ lat: 10, lng: 10, source: 'manual' }, bearer('entrepreneur', String(oid())))).status).toBe(404);
    expect((await patch({ lat: 10, lng: 10, source: 'manual' }, bearer('customer', owner))).status).toBe(403);
    expect((await request(app).patch(`${api}/businesses/${bid}/location`).send({ lat: 10, lng: 10, source: 'manual' })).status).toBe(401);
    expect(biz.save).not.toHaveBeenCalled();
  });
});

describe('public discovery', () => {
  const chain = (result) => {
    const c = {};
    for (const m of ['select', 'sort', 'skip', 'limit', 'populate']) c[m] = jest.fn(() => c);
    c.then = (res, rej) => Promise.resolve(result).then(res, rej);
    return c;
  };
  const shop = (lng, lat) => {
    const b = new Business({ owner: oid(), name: 'Shop', location: { coordinates: [lng, lat] }, verification: { status: 'approved' } });
    b.publicLocation = { type: 'Point', coordinates: geo.coarsen([lng, lat]) };
    return b;
  };

  test('nearby queries the coarsened index, hides the exact point, adds distance computed from the public point', async () => {
    const b = shop(77.594612, 12.971634);
    const c = chain([b]);
    const find = jest.spyOn(Business, 'find').mockReturnValue(c);
    const res = await request(app).get(`${api}/businesses/nearby?lat=12.9716&lng=77.5946&radiusKm=5`);
    expect(res.status).toBe(200);
    expect(find.mock.calls[0][0].publicLocation.$near.$geometry.coordinates).toEqual([77.5946, 12.9716]);
    expect(find.mock.calls[0][0].location).toBeUndefined();
    expect(c.select).toHaveBeenCalledWith(expect.stringContaining('-location'));
    const item = res.body.data[0];
    expect(item.location.coordinates).toEqual([77.595, 12.972]);     // coarse, same field name
    expect(JSON.stringify(res.body)).not.toContain('77.594612');     // exact never leaves
    expect(JSON.stringify(res.body)).not.toContain('12.971634');
    expect(item.publicLocation).toBeUndefined();
    expect(item.locationSource).toBeUndefined();
    expect(item.distanceKm).toBeGreaterThanOrEqual(0); expect(item.distanceKm).toBeLessThan(0.2);
  });
  test('distance is derived from the coarse point, so it cannot be used to recover the exact one', async () => {
    const a = shop(77.59461, 12.97163); const b = shop(77.59481, 12.97151); // two different exact points, same 110 m cell
    jest.spyOn(Business, 'find').mockReturnValueOnce(chain([a])).mockReturnValueOnce(chain([b]));
    const q = `${api}/businesses/nearby?lat=12.95&lng=77.55`;
    const ra = await request(app).get(q); const rb = await request(app).get(q);
    expect(ra.body.data[0].distanceKm).toBe(rb.body.data[0].distanceKm);
  });
  test('distance equals the distance to the COARSE point, at a position where exact vs coarse would round differently', async () => {
    const exact = [77.59461, 12.97163]; const coarse = geo.coarsen(exact);
    const r1 = (n) => Math.round(n * 10) / 10;
    let visitorLat = null;
    for (let lat = 12.90; lat < 12.96; lat += 0.0001) {
      if (r1(geo.haversineKm(lat, 77.55, coarse[1], coarse[0])) !== r1(geo.haversineKm(lat, 77.55, exact[1], exact[0]))) { visitorLat = lat; break; }
    }
    expect(visitorLat).not.toBeNull();
    jest.spyOn(Business, 'find').mockReturnValue(chain([shop(...exact)]));
    const res = await request(app).get(`${api}/businesses/nearby?lat=${visitorLat}&lng=77.55`);
    expect(res.body.data[0].distanceKm).toBe(r1(geo.haversineKm(visitorLat, 77.55, coarse[1], coarse[0])));
  });
  test('a legacy record that has an exact point but no public one exposes no location at all', async () => {
    const legacy = { _id: oid(), name: 'Old', location: { type: 'Point', coordinates: [77.594612, 12.971634] }, verification: { status: 'approved' } };
    jest.spyOn(Business, 'find').mockReturnValue(chain([legacy]));
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(1);
    const res = await request(app).get(`${api}/businesses`);
    expect(JSON.stringify(res.body)).not.toContain('77.594612');
    expect(res.body.data[0].location).toBeUndefined();
  });
  test('list and public getById never contain the exact point; owner still gets it', async () => {
    const b = shop(77.594612, 12.971634);
    jest.spyOn(Business, 'find').mockReturnValue(chain([b]));
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(1);
    const list = await request(app).get(`${api}/businesses`);
    expect(JSON.stringify(list.body)).not.toContain('77.594612');
    const q = { populate: jest.fn(async () => b) };
    jest.spyOn(Business, 'findById').mockReturnValue(q);
    const pub = await request(app).get(`${api}/businesses/${b._id}`);
    expect(JSON.stringify(pub.body)).not.toContain('77.594612');
    expect(pub.body.data.location.coordinates).toEqual([77.595, 12.972]);
    const own = await request(app).get(`${api}/businesses/${b._id}`).set(bearer('entrepreneur', String(b.owner)));
    expect(own.body.data.location.coordinates).toEqual([77.594612, 12.971634]);
  });
  test('shops with no location are simply absent from the public shape (no fake point)', async () => {
    const b = new Business({ owner: oid(), name: 'No loc', verification: { status: 'approved' } });
    jest.spyOn(Business, 'find').mockReturnValue(chain([b]));
    jest.spyOn(Business, 'countDocuments').mockResolvedValue(1);
    const res = await request(app).get(`${api}/businesses`);
    expect(res.body.data[0].location).toBeUndefined();
  });
  test('nearby input validation', async () => {
    for (const qs of ['lat=abc&lng=77', 'lat=95&lng=77', 'lat=12&lng=181', 'lat=12']) {
      expect((await request(app).get(`${api}/businesses/nearby?${qs}`)).status).toBe(422);
    }
  });
});

describe('addresses & order delivery location are validated', () => {
  let user;
  beforeEach(() => {
    user = new User({ email: 'a@example.com', name: 'A' });
    user.save = jest.fn(async () => user);
    jest.spyOn(User, 'findById').mockResolvedValue(user);
  });
  const patchMe = (body) => request(app).patch(`${api}/users/me`).set(bearer('customer')).send(body);
  test('valid address with a real location is accepted', async () => {
    const r = await patchMe({ addresses: [{ label: 'Home', line1: '12 MG Road', location: { type: 'Point', coordinates: [77.59, 12.97] } }] });
    expect(r.status).toBe(200);
  });
  test('address without location is fine (manual entry); the stored location is not a [0,0] default', async () => {
    expect((await patchMe({ addresses: [{ line1: '12 MG Road' }] })).status).toBe(200);
    expect(user.addresses[0].location?.coordinates?.length ?? 0).toBe(0);
  });
  test('bad coordinates / (0,0) / missing line1 / too many are rejected', async () => {
    const bad = [
      [{ line1: 'x', location: { coordinates: [200, 10] } }],
      [{ line1: 'x', location: { coordinates: [10, 95] } }],
      [{ line1: 'x', location: { coordinates: [0, 0] } }],
      [{ line1: 'x', location: { coordinates: [1] } }],
      [{ label: 'no line' }],
      Array.from({ length: 11 }, () => ({ line1: 'x' })),
    ];
    for (const addresses of bad) expect((await patchMe({ addresses })).status).toBe(422);
  });
  test('order delivery address location is validated', async () => {
    const base = { businessId: String(oid()), items: [{ productId: String(oid()), quantity: 1 }], deliveryAddress: { line1: 'x', city: 'B', pincode: '560001' } };
    for (const coordinates of [[500, 1], [1, 500], [0, 0], [1]]) {
      const r = await request(app).post(`${api}/orders`).set(bearer('customer'))
        .send({ ...base, deliveryAddress: { ...base.deliveryAddress, location: { type: 'Point', coordinates } } });
      expect(r.status).toBe(422);
    }
  });
});
