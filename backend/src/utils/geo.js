// Small, dependency-free geo helpers. Coordinates follow GeoJSON order: [longitude, latitude].
const isFiniteNum = (n) => typeof n === 'number' && Number.isFinite(n);

exports.isValidLatLng = (lat, lng) =>
  isFiniteNum(lat) && isFiniteNum(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
  // (0,0) is "null island": it is what an unset/failed location looks like, never a real home or shop.
  && !(lat === 0 && lng === 0);

/** Round to `decimals` places. 3 dp ≈ 110 m — enough for "nearby", not enough to find a front door. */
exports.coarsen = ([lng, lat], decimals = 3) => {
  const f = 10 ** decimals;
  return [Math.round(lng * f) / f, Math.round(lat * f) / f];
};

/** Great-circle distance in km (haversine). */
exports.haversineKm = (lat1, lng1, lat2, lng2) => {
  const R = 6371.0088;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
};
