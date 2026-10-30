const { productDescriptionSchema } = require('../src/validators/ai.validator');

test('the description writer accepts the five app languages and nothing else', () => {
  for (const language of ['English', 'Kannada', 'Hindi', 'Tamil', 'Telugu']) {
    expect(productDescriptionSchema.validate({ name: 'Bag', language }).error).toBeUndefined();
  }
  expect(productDescriptionSchema.validate({ name: 'Bag', language: 'Klingon' }).error).toBeDefined();
  expect(productDescriptionSchema.validate({ name: 'Bag' }).value.language).toBe('English');
});
