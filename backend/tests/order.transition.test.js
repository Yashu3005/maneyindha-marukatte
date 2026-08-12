const { VALID_TRANSITIONS } = require('../src/models/Order');

describe('Order state machine', () => {
  test('pending can go to confirmed', () => {
    expect(VALID_TRANSITIONS.pending).toContain('confirmed');
  });
  test('delivered cannot go back to preparing', () => {
    expect(VALID_TRANSITIONS.delivered || []).not.toContain('preparing');
  });
  test('picked_up must go through out_for_delivery before delivered', () => {
    expect(VALID_TRANSITIONS.picked_up).toEqual(['out_for_delivery']);
  });
});
