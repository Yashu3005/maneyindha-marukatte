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

describe('payment test mode and self-pickup', () => {
  const saved = { ...process.env };
  afterEach(() => { process.env = { ...saved }; });
  test('with Razorpay TEST keys the shop can confirm an unpaid online order; live keys keep the block', async () => {
    process.env.RAZORPAY_KEY_ID = 'rzp_test_abc';
    expect((await (await transitionWith({ method: 'razorpay', status: 'pending' })).run()).status).toBe('confirmed');
    process.env.RAZORPAY_KEY_ID = 'rzp_live_abc';
    await expect((await transitionWith({ method: 'razorpay', status: 'pending' })).run()).rejects.toMatchObject({ code: 'PAYMENT_PENDING' });
  });
  test('ALLOW_CONFIRM_WITHOUT_PAYMENT=true also opens the gate', async () => {
    delete process.env.RAZORPAY_KEY_ID;
    process.env.ALLOW_CONFIRM_WITHOUT_PAYMENT = 'true';
    expect((await (await transitionWith({ method: 'razorpay', status: 'pending' })).run()).status).toBe('confirmed');
  });
  const pickup = (isSelfPickup, from, to) => {
    const user = { id: String(oid()), role: 'entrepreneur' };
    const order = { _id: oid(), customer: oid(), business: oid(), status: from, items: [], isSelfPickup, payment: undefined };
    jest.spyOn(Order, 'findById').mockResolvedValue(order);
    jest.spyOn(Business, 'exists').mockResolvedValue({ _id: order.business });
    jest.spyOn(Order, 'findOneAndUpdate').mockResolvedValue({ ...order, status: to });
    return orderService.transition(order._id, to, user);
  };
  test('a ready self-pickup order is marked collected directly; a delivery order cannot skip the journey', async () => {
    expect((await pickup(true, 'ready', 'delivered')).status).toBe('delivered');
    await expect(pickup(false, 'ready', 'delivered')).rejects.toMatchObject({ statusCode: 422 });
  });
  test('a self-pickup order cannot go on a delivery run', async () => {
    await expect(pickup(true, 'ready', 'picked_up')).rejects.toMatchObject({ statusCode: 422 });
  });
});
