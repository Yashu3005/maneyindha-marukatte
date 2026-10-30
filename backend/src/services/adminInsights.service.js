// Read-only views for the administrator: owners, shops, products, badges and growth.
// Everything is computed from the live database on each request; nothing is cached, invented or estimated.
const Business = require('../models/Business');
const Product = require('../models/Product');
const User = require('../models/User');
const Order = require('../models/Order');
const AppError = require('../utils/AppError');
const { parsePage, isObjectId } = require('../utils/pagination');
const { coverOf } = require('../utils/shopPhoto');
const rewards = require('./rewards.service');

const ADMIN_ROLES = ['admin', 'super_admin'];
const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const round1 = (n) => Math.round(n * 10) / 10;
const rx = (q) => new RegExp(escapeRegex(String(q).trim().slice(0, 60)), 'i');
const idOf = (v) => String(v);

// One owner's numbers from their shops and the delivered-order totals per shop.
// Badges follow EXACTLY what the owner sees (rewards.getSellerBadges): only shops that are currently active count towards
// the badge, the rating and the video. Delivered / revenue totals cover every shop so the admin sees the real history.
function summarizeOwner(shops, orderRows) {
  const byShop = new Map((orderRows || []).map((r) => [idOf(r._id), r]));
  let delivered = 0; let revenue = 0; let badgeDelivered = 0; let ratingCount = 0; let ratingSum = 0; let onVideo = false;
  for (const s of shops) {
    const r = byShop.get(idOf(s._id));
    if (r) { delivered += r.orders; revenue += r.revenue; }
    if (s.isActive === false) continue;
    if (r) badgeDelivered += r.orders;
    ratingCount += s.rating?.count || 0;
    ratingSum += (s.rating?.avg || 0) * (s.rating?.count || 0);
    if (s.promoVideo?.review?.status === 'approved') onVideo = true;
  }
  const ratingAvg = ratingCount ? round1(ratingSum / ratingCount) : 0;
  const tier = rewards.sellerTierFor(badgeDelivered);
  return {
    shops: shops.length,
    activeShops: shops.filter((s) => s.isActive !== false).length,
    delivered, revenue,
    rating: { avg: ratingAvg, count: ratingCount },
    badge: { id: tier.id, label: tier.label, icon: tier.icon },
    achievements: { wellRated: ratingCount >= 5 && ratingAvg >= 4.5, onVideo },
  };
}

const deliveredByShop = (shopIds) => (shopIds.length
  ? Order.aggregate([
    { $match: { business: { $in: shopIds }, status: 'delivered' } },
    { $group: { _id: '$business', orders: { $sum: 1 }, revenue: { $sum: '$amounts.total' } } },
  ])
  : Promise.resolve([]));

// owner id (string) -> summary
async function summaries(ownerIds) {
  const shops = await Business.find({ owner: { $in: ownerIds }, deletedAt: null }).select('owner name rating isActive promoVideo.review.status').lean();
  const rows = await deliveredByShop(shops.map((s) => s._id));
  const byOwner = new Map();
  for (const s of shops) {
    const k = idOf(s.owner);
    if (!byOwner.has(k)) byOwner.set(k, []);
    byOwner.get(k).push(s);
  }
  const out = new Map();
  for (const id of ownerIds) out.set(idOf(id), summarizeOwner(byOwner.get(idOf(id)) || [], rows));
  return out;
}

const ownerFilter = async (q) => {
  const ownerIds = await Business.distinct('owner', { deletedAt: null });
  const filter = { _id: { $in: ownerIds }, role: { $nin: ADMIN_ROLES }, deletedAt: null };
  if (q) { const r = rx(q); filter.$or = [{ name: r }, { email: r }]; }
  return filter;
};

exports.owners = async ({ q, page, limit } = {}) => {
  const p = parsePage({ page, limit }, { defLimit: 20, maxLimit: 100 });
  const filter = await ownerFilter(q);
  const [users, total] = await Promise.all([
    User.find(filter).sort('-createdAt').skip(p.skip).limit(p.limit).select('name email phone isActive avatarUrl createdAt suspension').lean(),
    User.countDocuments(filter),
  ]);
  const sums = await summaries(users.map((u) => u._id));
  const items = users.map((u) => ({
    id: u._id, name: u.name, email: u.email, phone: u.phone, avatarUrl: u.avatarUrl,
    isActive: u.isActive !== false, suspensionReason: u.suspension?.reason, joinedAt: u.createdAt,
    ...sums.get(idOf(u._id)),
  }));
  return { items, meta: { page: p.page, limit: p.limit, total } };
};

exports.ownerDetail = async (id, now = new Date()) => {
  if (!isObjectId(String(id))) throw new AppError('Owner not found', 404);
  const user = await User.findOne({ _id: id, role: { $nin: ADMIN_ROLES }, deletedAt: null })
    .select('name email phone isActive avatarUrl createdAt suspension').lean();
  if (!user) throw new AppError('Owner not found', 404);
  const shops = await Business.find({ owner: id, deletedAt: null })
    .select('name isActive isOpen verification.status rating suspension createdAt promoVideo.review.status bannerUrl logoUrl gallery').lean();
  if (!shops.length) throw new AppError('Owner not found', 404);
  const shopIds = shops.map((s) => s._id);
  const since = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 5, 1));
  const [rows, products, monthly, badges] = await Promise.all([
    deliveredByShop(shopIds),
    Product.aggregate([{ $match: { business: { $in: shopIds }, deletedAt: null } }, { $group: { _id: '$business', n: { $sum: 1 } } }]),
    Order.aggregate([
      { $match: { business: { $in: shopIds }, createdAt: { $gte: since } } },
      { $group: { _id: { $dateToString: { format: '%Y-%m', date: '$createdAt' } }, count: { $sum: 1 },
        revenue: { $sum: { $cond: [{ $eq: ['$status', 'delivered'] }, '$amounts.total', 0] } } } },
    ]),
    rewards.getSellerBadges(id),
  ]);
  const prodBy = new Map(products.map((r) => [idOf(r._id), r.n]));
  const rowBy = new Map(rows.map((r) => [idOf(r._id), r]));
  return {
    owner: {
      id: user._id, name: user.name, email: user.email, phone: user.phone, avatarUrl: user.avatarUrl,
      isActive: user.isActive !== false, suspensionReason: user.suspension?.reason, joinedAt: user.createdAt,
    },
    summary: summarizeOwner(shops, rows),
    badges, // the very same object the owner sees on their own badges screen
    shops: shops.map((s) => ({
      id: s._id, name: s.name, coverUrl: coverOf(s), status: s.verification?.status, isActive: s.isActive !== false,
      isOpen: s.isOpen !== false, suspensionReason: s.suspension?.reason, rating: s.rating || { avg: 0, count: 0 },
      products: prodBy.get(idOf(s._id)) || 0, delivered: rowBy.get(idOf(s._id))?.orders || 0, revenue: rowBy.get(idOf(s._id))?.revenue || 0,
    })),
    monthly: exports.fillMonths(monthly, 6, now, ['count', 'revenue']),
  };
};

exports.shops = async ({ q, status, page, limit } = {}) => {
  const p = parsePage({ page, limit }, { defLimit: 20, maxLimit: 100 });
  const filter = { deletedAt: null };
  if (status === 'suspended') filter.isActive = false;
  else if (['approved', 'in_review', 'pending', 'rejected'].includes(status)) filter['verification.status'] = status;
  if (q) filter.name = rx(q);
  const [shops, total] = await Promise.all([
    Business.find(filter).sort('-createdAt').skip(p.skip).limit(p.limit)
      .select('owner name isActive isOpen verification.status rating suspension createdAt bannerUrl logoUrl gallery')
      .populate('owner', 'name email').lean(),
    Business.countDocuments(filter),
  ]);
  const ids = shops.map((s) => s._id);
  const [rows, products] = await Promise.all([
    deliveredByShop(ids),
    ids.length ? Product.aggregate([{ $match: { business: { $in: ids }, deletedAt: null } }, { $group: { _id: '$business', n: { $sum: 1 } } }]) : [],
  ]);
  const rowBy = new Map(rows.map((r) => [idOf(r._id), r]));
  const prodBy = new Map(products.map((r) => [idOf(r._id), r.n]));
  const items = shops.map((s) => ({
    id: s._id, name: s.name, coverUrl: coverOf(s),
    owner: s.owner ? { id: s.owner._id, name: s.owner.name, email: s.owner.email } : null,
    status: s.verification?.status, isActive: s.isActive !== false, isOpen: s.isOpen !== false,
    suspension: s.suspension?.at ? { reason: s.suspension.reason, at: s.suspension.at, byOwner: !!s.suspension.byOwner } : null,
    rating: s.rating || { avg: 0, count: 0 }, products: prodBy.get(idOf(s._id)) || 0,
    delivered: rowBy.get(idOf(s._id))?.orders || 0, revenue: rowBy.get(idOf(s._id))?.revenue || 0, createdAt: s.createdAt,
  }));
  return { items, meta: { page: p.page, limit: p.limit, total } };
};

exports.products = async ({ q, business, page, limit } = {}) => {
  const p = parsePage({ page, limit }, { defLimit: 20, maxLimit: 100 });
  const filter = { deletedAt: null };
  if (business) {
    if (!isObjectId(String(business))) throw new AppError('Invalid shop id', 422);
    filter.business = business;
  }
  if (q) filter.name = rx(q);
  const [items, total] = await Promise.all([
    Product.find(filter).sort('-createdAt').skip(p.skip).limit(p.limit)
      .select('name price stock lowStockThreshold isActive images business createdAt').populate('business', 'name').lean(),
    Product.countDocuments(filter),
  ]);
  return {
    items: items.map((x) => ({
      id: x._id, name: x.name, price: x.price, stock: x.stock ?? 0,
      lowStock: (x.stock ?? 0) <= (x.lowStockThreshold ?? 5), isActive: x.isActive !== false,
      imageUrl: (x.images || []).find((u) => typeof u === 'string' && /^https:\/\//.test(u)),
      shop: x.business ? { id: x.business._id, name: x.business.name } : null, createdAt: x.createdAt,
    })),
    meta: { page: p.page, limit: p.limit, total },
  };
};

exports.badges = async () => {
  const ownerIds = await Business.distinct('owner', { deletedAt: null });
  const users = ownerIds.length
    ? await User.find({ _id: { $in: ownerIds }, role: { $nin: ADMIN_ROLES }, deletedAt: null }).select('name email isActive').lean()
    : [];
  const sums = await summaries(users.map((u) => u._id));
  const list = users.map((u) => ({ id: u._id, name: u.name, email: u.email, isActive: u.isActive !== false, ...sums.get(idOf(u._id)) }));
  return {
    totalOwners: list.length,
    tiers: rewards.SELLER_TIERS.map((t) => ({ id: t.id, label: t.label, icon: t.icon, min: t.min, owners: list.filter((o) => o.badge.id === t.id).length })),
    achievements: [
      { id: 'well_rated', label: 'Highly Rated', icon: '⭐', owners: list.filter((o) => o.achievements.wellRated).length },
      { id: 'on_video', label: 'On Camera', icon: '🎬', owners: list.filter((o) => o.achievements.onVideo).length },
    ],
    leaders: [...list]
      .sort((a, b) => b.delivered - a.delivered || b.rating.avg - a.rating.avg)
      .slice(0, 10)
      .map((o) => ({ id: o.id, name: o.name, badge: o.badge, delivered: o.delivered, revenue: o.revenue, rating: o.rating, achievements: o.achievements })),
  };
};

// ---- growth ----
// The last n calendar months (UTC), oldest first, zero-filled. Rows look like { _id: '2026-10', count, ... }.
exports.fillMonths = (rows, n, now = new Date(), fields = ['count']) => {
  const by = new Map((rows || []).map((r) => [r._id, r]));
  const out = [];
  for (let i = n - 1; i >= 0; i -= 1) {
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
    const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
    const row = by.get(key) || {};
    out.push({ month: key, ...Object.fromEntries(fields.map((f) => [f, row[f] || 0])) });
  }
  return out;
};

// % change from the previous month; null when there is nothing to compare with.
exports.pctChange = (cur, prev) => (prev > 0 ? round1(((cur - prev) / prev) * 100) : null);

exports.growth = async ({ months } = {}, now = new Date()) => {
  const n = Math.min(12, Math.max(3, parseInt(months, 10) || 6));
  const since = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - (n - 1), 1));
  const month = { $dateToString: { format: '%Y-%m', date: '$createdAt' } };
  const people = { deletedAt: null, role: { $nin: ADMIN_ROLES }, createdAt: { $gte: since } };
  const [customers, owners, shops, orders, uCount, shopCount, approved, productCount, orderTotals] = await Promise.all([
    User.aggregate([{ $match: { ...people, role: 'customer' } }, { $group: { _id: month, count: { $sum: 1 } } }]),
    User.aggregate([{ $match: { ...people, role: 'entrepreneur' } }, { $group: { _id: month, count: { $sum: 1 } } }]),
    Business.aggregate([{ $match: { deletedAt: null, createdAt: { $gte: since } } }, { $group: { _id: month, count: { $sum: 1 } } }]),
    Order.aggregate([
      { $match: { createdAt: { $gte: since } } },
      { $group: { _id: month, count: { $sum: 1 }, revenue: { $sum: { $cond: [{ $eq: ['$status', 'delivered'] }, '$amounts.total', 0] } } } },
    ]),
    User.aggregate([{ $match: { deletedAt: null, role: { $in: ['customer', 'entrepreneur'] } } }, { $group: { _id: '$role', n: { $sum: 1 } } }]),
    Business.countDocuments({ deletedAt: null }),
    Business.countDocuments({ deletedAt: null, isActive: true, 'verification.status': 'approved' }),
    Product.countDocuments({ deletedAt: null, isActive: true }),
    Order.aggregate([{ $group: { _id: '$status', n: { $sum: 1 }, amount: { $sum: '$amounts.total' } } }]),
  ]);
  const c = exports.fillMonths(customers, n, now); const o = exports.fillMonths(owners, n, now);
  const s = exports.fillMonths(shops, n, now); const ord = exports.fillMonths(orders, n, now, ['count', 'revenue']);
  const series = c.map((row, i) => ({
    month: row.month, customers: row.count, entrepreneurs: o[i].count, shops: s[i].count, orders: ord[i].count, revenue: ord[i].revenue,
  }));
  const last = series[series.length - 1]; const prev = series[series.length - 2];
  const roleN = (r) => uCount.find((x) => x._id === r)?.n || 0;
  const delivered = orderTotals.find((x) => x._id === 'delivered');
  return {
    months: n, series,
    thisMonth: last,
    change: Object.fromEntries(['customers', 'entrepreneurs', 'shops', 'orders', 'revenue'].map((k) => [k, exports.pctChange(last[k], prev[k])])),
    totals: {
      customers: roleN('customer'), entrepreneurs: roleN('entrepreneur'), shops: shopCount, approvedShops: approved, products: productCount,
      orders: orderTotals.reduce((t, r) => t + r.n, 0), deliveredOrders: delivered?.n || 0, revenue: delivered?.amount || 0,
    },
  };
};

exports._summarizeOwner = summarizeOwner;
