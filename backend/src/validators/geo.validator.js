const Joi = require('joi');
const { isValidLatLng } = require('../utils/geo');

// GeoJSON order [lng, lat], range-checked, and never the (0,0) placeholder.
exports.coordinates = Joi.array().ordered(
  Joi.number().min(-180).max(180).required(),
  Joi.number().min(-90).max(90).required()
).length(2).custom((v, helpers) => (isValidLatLng(v[1], v[0]) ? v : helpers.error('any.invalid')), 'real location');

exports.point = Joi.object({ type: Joi.string().valid('Point'), coordinates: exports.coordinates.required() });

const optStr = (max) => Joi.string().trim().max(max).allow('');
exports.address = Joi.object({
  label: optStr(40), line1: Joi.string().trim().min(1).max(200).required(), line2: optStr(200),
  city: optStr(100), state: optStr(100), pincode: optStr(10),
  location: exports.point,
});

exports.setLocationSchema = Joi.object({
  lat: Joi.number().min(-90).max(90).required(),
  lng: Joi.number().min(-180).max(180).required(),
  source: Joi.string().valid('device', 'manual').required(),
}).custom((v, helpers) => (isValidLatLng(v.lat, v.lng) ? v : helpers.error('any.invalid')), 'real location');

exports.updateMeSchema = Joi.object({
  name: Joi.string().trim().min(1).max(100),
  phone: Joi.string().trim().pattern(/^[0-9+\-\s()]{7,20}$/),
  language: Joi.string().trim().max(10),
  addresses: Joi.array().items(exports.address).max(10),
  bankAccount: Joi.object().unknown(true),
});
