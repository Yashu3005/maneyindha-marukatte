const { computeDiscount } = require('../src/services/cart.service');

describe('Coupon discount computation', () => {
  test('percent coupon respects maxDiscount cap', () => {
    const coupon = { type: 'percent', value: 50, maxDiscount: 100 };
    expect(computeDiscount(coupon, 1000)).toBe(100);
  });
  test('flat coupon never exceeds subtotal', () => {
    const coupon = { type: 'flat', value: 500 };
    expect(computeDiscount(coupon, 200)).toBe(200);
  });
  test('percent without cap', () => {
    const coupon = { type: 'percent', value: 10 };
    expect(computeDiscount(coupon, 450)).toBe(45);
  });
});
