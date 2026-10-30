const mongoose = require('mongoose');
const Coupon = require('../models/Coupon');
const Business = require('../models/Business');
const Order = require('../models/Order');

// Customer rewards. Coupons unlock by how many orders a customer has actually had DELIVERED (and how recently).
// (Badges belong to the entrepreneurs; see getSellerBadges below.) Nothing here is hand-picked per user, and every number comes from real orders.
const TIERS = [
  { id: 'new', label: 'New Member', min: 0, icon: '🌱', blurb: 'Welcome! Your first delivered order earns your first badge.' },
  { id: 'explorer', label: 'Explorer', min: 1, icon: '🧭', blurb: 'You have tried your first home-made treat.' },
  { id: 'regular', label: 'Regular', min: 3, icon: '⭐', blurb: 'A familiar face — local makers know you by now.' },
  { id: 'loyal', label: 'Loyal Patron', min: 6, icon: '💛', blurb: 'You keep women entrepreneurs in business.' },
  { id: 'champion', label: 'Marukatte Champion', min: 12, icon: '🏆', blurb: 'One of our most devoted customers.' },
];

const PROGRAMME = [
  { code: 'WELCOME10', title: 'Welcome offer', description: '10% off your first order (up to ₹50)',
    type: 'percent', value: 10, maxDiscount: 50, minOrderAmount: 100, maxDeliveredOrders: 0, audience: 'new' },
  { code: 'REGULAR5', title: 'Reward after 3 orders', description: '5% off (up to ₹40) — after 3 delivered orders',
    type: 'percent', value: 5, maxDiscount: 40, minOrderAmount: 150, minDeliveredOrders: 3, audience: 'regular' },
  { code: 'LOYAL10', title: 'Reward after 6 orders', description: '10% off (up to ₹75) — after 6 delivered orders',
    type: 'percent', value: 10, maxDiscount: 75, minOrderAmount: 200, minDeliveredOrders: 6, audience: 'regular' },
  { code: 'CHAMPION100', title: 'Reward after 12 orders', description: '₹100 off orders above ₹300 — after 12 delivered orders',
    type: 'flat', value: 100, minOrderAmount: 300, minDeliveredOrders: 12, audience: 'regular' },
];

const DAY = 24 * 60 * 60 * 1000;
exports.TIERS = TIERS;
exports.PROGRAMME = PROGRAMME;
exports.isRewardCode = (code) => PROGRAMME.some((p) => p.code === String(code || '').toUpperCase());

/** Creates the reward coupons if they do not exist yet. Safe to call any number of times. */
exports.ensureRewardCoupons = async () => {
  await Promise.all(PROGRAMME.map((p) => {
    const doc = { ...p };
    delete doc.audience; // audience is a label for the UI, not a stored field
    const { title, description } = doc;
    delete doc.title; delete doc.description;
    return Coupon.updateOne(
      { code: p.code },
      // Only the wording is refreshed; amounts, limits and anything an admin edited stay as they are.
      { $set: { title, description }, $setOnInsert: { ...doc, isReward: true, usageLimitPerUser: 1, isActive: true } },
      { upsert: true }
    );
  }));
};

exports.tierFor = (delivered) => [...TIERS].reverse().find((t) => delivered >= t.min) || TIERS[0];

exports.frequencyLabel = (last30, last90) => {
  if (last30 >= 4) return 'Weekly regular';
  if (last30 >= 2) return 'Ordering often this month';
  if (last30 === 1) return 'Ordered this month';
  if (last90 > 0) return 'Ordered in the last 3 months';
  return null;
};

exports.customerStats = async (customerId, now = new Date()) => {
  const d30 = new Date(now.getTime() - 30 * DAY);
  const d90 = new Date(now.getTime() - 90 * DAY);
  const [row] = await Order.aggregate([
    { $match: { customer: new mongoose.Types.ObjectId(String(customerId)), status: 'delivered' } },
    { $group: {
      _id: null,
      delivered: { $sum: 1 },
      spent: { $sum: '$amounts.total' },
      last30: { $sum: { $cond: [{ $gte: ['$createdAt', d30] }, 1, 0] } },
      last90: { $sum: { $cond: [{ $gte: ['$createdAt', d90] }, 1, 0] } },
      firstOrderAt: { $min: '$createdAt' },
      lastOrderAt: { $max: '$createdAt' },
    } },
  ]);
  return { delivered: row?.delivered || 0, spent: row?.spent || 0, last30: row?.last30 || 0, last90: row?.last90 || 0,
    firstOrderAt: row?.firstOrderAt || null, lastOrderAt: row?.lastOrderAt || null };
};

/** Badge, progress to the next one, and every reward coupon with its status for this customer. */
exports.getRewards = async (customerId, now = new Date()) => {
  await exports.ensureRewardCoupons();
  const stats = await exports.customerStats(customerId, now);
  const tier = exports.tierFor(stats.delivered);
  const next = TIERS.find((t) => t.min > stats.delivered) || null;

  const codes = PROGRAMME.map((p) => p.code);
  const [coupons, used] = await Promise.all([
    Coupon.find({ code: { $in: codes }, isActive: true }),
    Order.aggregate([
      { $match: { customer: new mongoose.Types.ObjectId(String(customerId)), 'coupon.code': { $in: codes },
        status: { $nin: ['cancelled', 'rejected', 'payment_failed'] } } },
      { $group: { _id: '$coupon.code', n: { $sum: 1 } } },
    ]),
  ]);
  const usedBy = new Map(used.map((u) => [u._id, u.n]));

  const list = [];
  for (const def of PROGRAMME) {
    const c = coupons.find((x) => x.code === def.code);
    if (!c) continue;
    const base = {
      code: c.code, title: def.title, description: def.description, type: c.type, value: c.value,
      maxDiscount: c.maxDiscount || null, minOrderAmount: c.minOrderAmount || 0, audience: def.audience,
    };
    if ((usedBy.get(c.code) || 0) >= (c.usageLimitPerUser || 1)) { list.push({ ...base, status: 'used' }); continue; }
    if (c.maxDeliveredOrders != null && stats.delivered > c.maxDeliveredOrders) continue; // welcome offer has ended: hide it
    if (c.minDeliveredOrders != null && stats.delivered < c.minDeliveredOrders) {
      const need = c.minDeliveredOrders - stats.delivered;
      list.push({ ...base, status: 'locked', unlockHint: `Unlocks after ${need} more delivered order${need === 1 ? '' : 's'}` });
      continue;
    }
    list.push({ ...base, status: 'available' });
  }

  return {
    badge: { id: tier.id, label: tier.label, icon: tier.icon, blurb: tier.blurb },
    badges: TIERS.map((t) => ({ id: t.id, label: t.label, icon: t.icon, min: t.min, earned: stats.delivered >= t.min })),
    next: next ? { id: next.id, label: next.label, icon: next.icon, ordersToGo: next.min - stats.delivered } : null,
    stats: {
      deliveredOrders: stats.delivered, totalSpent: stats.spent,
      last30Days: stats.last30, last90Days: stats.last90,
      frequency: exports.frequencyLabel(stats.last30, stats.last90),
      memberSince: stats.firstOrderAt,
    },
    coupons: list,
  };
};

// ---- Entrepreneur badges -------------------------------------------------------------------------
// Badges are for the women entrepreneurs: they come from orders their shops have actually DELIVERED, plus
// a couple of achievements (customer ratings, an approved shop video). Customers earn coupons, not badges.
const SELLER_TIERS = [
  { id: 'new_maker', label: 'New Entrepreneur', min: 0, icon: '🌱', blurb: 'Welcome! Your first delivered order earns your first badge.' },
  { id: 'first_sale', label: 'First Sale', min: 1, icon: '🎉', blurb: 'Your first order reached a happy customer.' },
  { id: 'rising', label: 'Rising Maker', min: 10, icon: '🌟', blurb: 'Customers are coming back for your products.' },
  { id: 'trusted', label: 'Trusted Maker', min: 30, icon: '🤝', blurb: 'A name your neighbourhood trusts.' },
  { id: 'star', label: 'Star Entrepreneur', min: 100, icon: '🏆', blurb: 'One of our most successful home businesses.' },
];
exports.SELLER_TIERS = SELLER_TIERS;
exports.sellerTierFor = (delivered) => [...SELLER_TIERS].reverse().find((t) => delivered >= t.min) || SELLER_TIERS[0];

exports.getSellerBadges = async (ownerId) => {
  const shops = await Business.find({ owner: ownerId, isActive: true }).select('rating promoVideo').lean();
  const ids = shops.map((s) => s._id);
  const delivered = ids.length ? await Order.countDocuments({ business: { $in: ids }, status: 'delivered' }) : 0;

  let ratingCount = 0; let ratingSum = 0;
  for (const s of shops) { ratingCount += s.rating?.count || 0; ratingSum += (s.rating?.avg || 0) * (s.rating?.count || 0); }
  const ratingAvg = ratingCount ? Math.round((ratingSum / ratingCount) * 10) / 10 : 0;
  const hasVideo = shops.some((s) => s.promoVideo?.review?.status === 'approved');

  const tier = exports.sellerTierFor(delivered);
  const next = SELLER_TIERS.find((t) => t.min > delivered) || null;
  return {
    badge: { id: tier.id, label: tier.label, icon: tier.icon, blurb: tier.blurb },
    badges: SELLER_TIERS.map((t) => ({ id: t.id, label: t.label, icon: t.icon, min: t.min, earned: delivered >= t.min })),
    next: next ? { id: next.id, label: next.label, icon: next.icon, ordersToGo: next.min - delivered } : null,
    achievements: [
      { id: 'well_rated', label: 'Highly Rated', icon: '⭐', earned: ratingCount >= 5 && ratingAvg >= 4.5,
        hint: 'An average of 4.5★ or more from at least 5 reviews' },
      { id: 'on_video', label: 'On Camera', icon: '🎬', earned: hasVideo, hint: 'Get a shop video approved by the admin' },
    ],
    stats: { deliveredOrders: delivered, rating: { avg: ratingAvg, count: ratingCount } },
  };
};
