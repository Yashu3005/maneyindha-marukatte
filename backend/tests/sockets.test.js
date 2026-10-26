const { oid } = require('./helpers');
const Order = require('../src/models/Order');
const Business = require('../src/models/Business');
const { canJoin } = require('../src/sockets');

const cust = oid().toString();
const owner = oid().toString();
const partner = oid().toString();
const order = { customer: cust, business: oid(), deliveryPartner: partner };
beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(Order, 'findById').mockReturnValue({ select: async () => order });
  jest.spyOn(Business, 'exists').mockImplementation(async (q) => (q.owner === owner ? { _id: 1 } : null));
});
const room = `order:${oid()}`;

describe('socket room authorization', () => {
  test('participants may join their order room', async () => {
    expect(await canJoin({ id: cust, role: 'customer' }, room)).toBe(true);
    expect(await canJoin({ id: partner, role: 'delivery_partner' }, room)).toBe(true);
    expect(await canJoin({ id: owner, role: 'entrepreneur' }, room)).toBe(true);
    expect(await canJoin({ id: oid().toString(), role: 'admin' }, room)).toBe(true);
  });
  test('strangers cannot eavesdrop on someone else\'s order', async () => {
    expect(await canJoin({ id: oid().toString(), role: 'customer' }, room)).toBe(false);
    expect(await canJoin({ id: oid().toString(), role: 'entrepreneur' }, room)).toBe(false);
  });
  test('missing order, malformed ids, chat:* and non-strings are refused', async () => {
    Order.findById.mockReturnValue({ select: async () => null });
    expect(await canJoin({ id: cust, role: 'customer' }, room)).toBe(false);
    expect(await canJoin({ id: cust, role: 'customer' }, 'order:xyz')).toBe(false);
    expect(await canJoin({ id: cust, role: 'customer' }, 'chat:anything')).toBe(false);
    expect(await canJoin({ id: cust, role: 'customer' }, { $ne: 1 })).toBe(false);
  });
  test('personal room only for yourself', async () => {
    expect(await canJoin({ id: cust, role: 'customer' }, `user:${cust}`)).toBe(true);
    expect(await canJoin({ id: cust, role: 'customer' }, `user:${owner}`)).toBe(false);
  });
});
