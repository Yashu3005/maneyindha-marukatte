// The one rule for "which picture represents a shop": the cover (bannerUrl), then the logo, then the first
// gallery photo — but only a real https URL. Nothing is ever invented; a shop with none simply has none.
const isHttps = (u) => typeof u === 'string' && /^https:\/\/[^\s]+$/.test(u.trim());

function coverOf(shop) {
  const candidates = [shop?.bannerUrl, shop?.logoUrl, ...(Array.isArray(shop?.gallery) ? shop.gallery : [])];
  const found = candidates.find(isHttps);
  return found ? found.trim() : undefined;
}

module.exports = { coverOf, isHttps };
