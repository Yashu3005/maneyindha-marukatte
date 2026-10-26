// Documentation drift guard: every route the app really serves must be in openapi.json, and vice versa.
const mongoose = require('mongoose');
mongoose.set('bufferCommands', false);
const app = require('../src/app');
const spec = require('../src/docs/openapi.json');

function liveRoutes() {
  const out = new Set();
  const walk = (stack, prefix) => {
    for (const l of stack) {
      if (l.route) {
        for (const m of Object.keys(l.route.methods)) out.add(`${m.toUpperCase()} ${prefix}${l.route.path}`);
      } else if (l.name === 'router' && l.handle.stack) {
        const src = l.regexp.source.replace('\\/?(?=\\/|$)', '').replace(/^\^/, '').replace(/\\\//g, '/').replace(/\$$/, '');
        walk(l.handle.stack, prefix + src);
      }
    }
  };
  walk(app._router.stack, '');
  return out;
}
const norm = (p) => p.replace(/^\/api\/v1/, '').replace(/:([A-Za-z]+)/g, '{$1}').replace(/(.)\/$/, '$1');

test('every served route is documented and every documented route is served', () => {
  const live = new Set([...liveRoutes()].map((r) => { const [m, p] = r.split(' '); return `${m} ${norm(p)}`; }));
  const doc = new Set();
  for (const [p, ops] of Object.entries(spec.paths)) for (const m of Object.keys(ops)) doc.add(`${m.toUpperCase()} ${p}`);
  live.delete('GET /api/docs'); // swagger UI itself
  expect([...live].filter((r) => !doc.has(r))).toEqual([]);
  expect([...doc].filter((r) => !live.has(r))).toEqual([]);
});

test('spec is structurally sound: refs resolve, ops have responses, path params declared', () => {
  const refs = JSON.stringify(spec).match(/#\/components\/schemas\/[A-Za-z]+/g) || [];
  for (const r of refs) expect(spec.components.schemas[r.split('/').pop()]).toBeDefined();
  for (const [p, ops] of Object.entries(spec.paths)) {
    for (const [m, o] of Object.entries(ops)) {
      expect(Object.keys(o.responses || {}).length).toBeGreaterThan(0);
      for (const name of (p.match(/\{(\w+)\}/g) || []).map((s) => s.slice(1, -1))) {
        expect((o.parameters || []).some((x) => x.name === name && x.in === 'path')).toBe(true);
      }
      expect(['get', 'post', 'patch', 'put', 'delete']).toContain(m);
    }
  }
});

test('no secret-looking values are present in the spec', () => {
  expect(JSON.stringify(spec)).not.toMatch(/re_[A-Za-z0-9]{20,}|rzp_(test|live)_[A-Za-z0-9]{8,}|AIza[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9]{20,}/);
});
