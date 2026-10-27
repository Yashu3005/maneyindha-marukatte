const mongoose = require('mongoose');
const Coupon = require('../models/Coupon');
const Order = require('../models/Order');

// Loyalty programme. Badges come from how many orders a customer has actually had DELIVERED (and how recently);
// reward coupons unlock with those badges. Nothing here is hand-picked per user, and every number comes from real orders.
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
  { code: 'REGULAR5', title: 'Regular customer reward', description: '5% off (up to ₹40) — for Regulars',
    type: 'percent', value: 5, maxDiscount: 40, minOrderAmount: 150, minDeliveredOrders: 3, audience: 'regular' },
  { code: 'LOYAL10', title: 'Loyal Patron reward', description: '10% off (up to ₹75) — for Loyal Patrons',
    type: 'percent', value: 10, maxDiscount: 75, minOrderAmount: 200, minDeliveredOrders: 6, audience: 'regular' },
  { code: 'CHAMPION100', title: 'Champion reward', description: '₹100 off orders above ₹300 — for Champions',
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
    return Coupon.updateOne(
      { code: p.code },
      { $setOnInsert: { ...doc, isReward: true, usageLimitPerUser: 1, isActive: true } },
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
