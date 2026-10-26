const AppError = require('../utils/AppError');

// Joi validation middleware. Usage: validate(schema, 'body' | 'query' | 'params')
module.exports = (schema, target = 'body') => (req, _res, next) => {
  const { error, value } = schema.validate(req[target], { abortEarly: false, stripUnknown: true });
  if (error) return next(new AppError(error.details.map((d) => d.message).join('; '), 422));
  req[target] = value;
  next();
};
