// Minimal in-memory stand-in for the handful of Mongoose model statics the OTP/session
// code uses (findOne, findOneAndUpdate, updateOne, deleteOne, deleteMany, create).
// It supports exactly the query/update operators those code paths use ($gt, $lt, $set, $inc).
let counter = 0;

function matches(row, query) {
  return Object.entries(query).every(([k, v]) => {
    const val = row[k];
    if (v && typeof v === 'object' && !(v instanceof Date) && !Array.isArray(v) && !(v && v._bsontype)) {
      if ('$gt' in v && !(val > v.$gt)) return false;
      if ('$lt' in v && !(val < v.$lt)) return false;
      return true;
    }
    if (v === null) return val === null || val === undefined;
    return String(val) === String(v);
  });
}

function apply(row, update) {
  const before = JSON.stringify(row);
  Object.assign(row, update.$set || {});
  for (const [k, n] of Object.entries(update.$inc || {})) row[k] = (row[k] || 0) + n;
  return before !== JSON.stringify(row);
}

exports.installMemoryModel = (Model, defaults = {}) => {
  const rows = [];
  const find = (q) => rows.find((r) => matches(r, q));
  jest.spyOn(Model, 'findOne').mockImplementation(async (q) => find(q) || null);
  jest.spyOn(Model, 'findOneAndUpdate').mockImplementation(async (q, update, opts = {}) => {
    let row = find(q);
    if (!row) {
      if (!opts.upsert) return null;
      row = { _id: `id${++counter}`, ...defaults };
      for (const [k, v] of Object.entries(q)) if (typeof v !== 'object' || v === null) row[k] = v;
      rows.push(row);
    }
    apply(row, update);
    return row;
  });
  jest.spyOn(Model, 'updateOne').mockImplementation(async (q, update) => {
    const row = find(q);
    return { modifiedCount: row && apply(row, update) ? 1 : 0 };
  });
  jest.spyOn(Model, 'deleteOne').mockImplementation(async (q) => {
    const i = rows.findIndex((r) => matches(r, q));
    if (i >= 0) rows.splice(i, 1);
    return { deletedCount: i >= 0 ? 1 : 0 };
  });
  jest.spyOn(Model, 'deleteMany').mockImplementation(async (q) => {
    let n = 0;
    for (let i = rows.length - 1; i >= 0; i -= 1) if (matches(rows[i], q)) { rows.splice(i, 1); n += 1; }
    return { deletedCount: n };
  });
  return rows;
};

// Stand-in for the Resend SDK client: records every send and can be told to fail.
exports.fakeResendClient = () => {
  const sent = [];
  const client = {
    sent,
    mode: 'ok',
    emails: {
      send: jest.fn(async (msg) => {
        sent.push(msg);
        if (client.mode === 'throw') throw new Error('socket hang up');
        if (client.mode === 'invalid_api_key') return { data: null, error: { name: 'invalid_api_key', message: 'API key is invalid' } };
        if (client.mode === 'rate_limit') return { data: null, error: { name: 'rate_limit_exceeded', message: 'slow down', statusCode: 429 } };
        return { data: { id: `em_${sent.length}` }, error: null };
      }),
      get: jest.fn(async (id) => ({ data: { id, last_event: 'delivered', to: ['x@example.com'], created_at: 'now' }, error: null })),
    },
  };
  return client;
};
exports.codeFromEmail = (msg) => /\b(\d{6})\b/.exec(msg.text)[1];
