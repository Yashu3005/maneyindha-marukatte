const Order = require('../src/models/Order');
const Business = require('../src/models/Business');
const orderService = require('../src/services/order.service');
const { oid } = require('./helpers');

beforeEach(() => jest.restoreAllMocks());

async function transitionWith(payment) {
  const user = { id: String(oid()), role: 'entrepreneur' };
  const order = { _id: oid(), customer: oid(), business: oid(), status: 'pending', items: [], payment };
  jest.spyOn(Order, 'findById').mockResolvedValue(order);
  jest.spyOn(Business, 'exists').mockResolvedValue({ _id: order.business });
  const upd = jest.spyOn(Order, 'findOneAndUpdate').mockResolvedValue({ ...order, status: 'confirmed' });
  return { run: () => orderService.transition(order._id, 'confirmed', user), upd };
}

test('shop cannot confirm an online-payment order until payment is confirmed', async () => {
  const { run, upd } = await transitionWith({ method: 'razorpay', status: 'pending' });
  await expect(run()).rejects.toMatchObject({ statusCode: 409, code: 'PAYMENT_PENDING' });
  expect(upd).not.toHaveBeenCalled();
});
test('failed online payment cannot be confirmed either', async () => {
  const { run } = await transitionWith({ method: 'razorpay', status: 'failed' });
  await expect(run()).rejects.toMatchObject({ statusCode: 409 });
});
test('paid online order and COD order can be confirmed', async () => {
  expect((await (await transitionWith({ method: 'razorpay', status: 'paid' })).run()).status).toBe('confirmed');
  expect((await (await transitionWith({ method: 'cod', status: 'pending' })).run()).status).toBe('confirmed');
  expect((await (await transitionWith(undefined)).run()).status).toBe('confirmed'); // legacy orders
});
