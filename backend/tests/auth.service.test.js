process.env.JWT_SECRET = 'test-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh';

const jwt = require('jsonwebtoken');

describe('JWT config sanity', () => {
  test('access and refresh use different secrets', () => {
    const payload = { id: 'x', role: 'customer' };
    const access = jwt.sign(payload, process.env.JWT_SECRET);
    expect(() => jwt.verify(access, process.env.JWT_REFRESH_SECRET)).toThrow();
  });
});
