const Business = require('../models/Business');
const Notification = require('../models/Notification');
const User = require('../models/User');
const Order = require('../models/Order');
const Review = require('../models/Review');
const Coupon = require('../models/Coupon');
const RefreshSession = require('../models/RefreshSession');
const AppError = require('../utils/AppError');
const notifications = require('./notification.service');
const email = require('./email.service');
const { parsePage } = require('../utils/pagination');

const ADMIN_ROLES = ['admin', 'super_admin'];
const REQUIRED_DOCS = ['id_proof', 'business_proof'];
const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

exports.listVerificationRequests = async ({ status = 'pending', page = 1, limit = 20 }) => {
  const filter = { 'verification.status': status };
  const [items, total] = await Promise.all([
    Business.find(filter).sort('createdAt')
      .skip((page - 1) * limit).limit(Number(limit))
      .populate('owner', 'name email phone'),
    Business.countDocuments(filter),
  ]);
  return { items, meta: { page: Number(page), limit: Number(limit), total } };
};

/**
 * Review an application. A shop only goes live when an admin approves it, and only once it has been
 * SUBMITTED (in_review) with the required documents actually on file — never straight from "pending".
 */
exports.reviewBusiness = async (adminId, businessId, { action, reason }) => {
  const business = await Business.findById(businessId);
  if (!business) throw new AppError('Business not found', 404);

  const status = business.verification.status;
  if (!['pending', 'in_review'].includes(status)) {
    throw new AppError(`Business is already ${status}`, 422);
  }

  if (action === 'approve') {
    if (status !== 'in_review') {
      throw new AppError('This shop has not submitted its application for review yet', 422, 'NOT_SUBMITTED');
    }
    const docs = business.verification.documents || [];
    const missing = REQUIRED_DOCS.filter((t) => !docs.some((d) => d.type === t && d.publicId));
    if (missing.length) {
      throw new AppError('Required documents are missing (ID proof and business proof must be uploaded)', 422, 'DOCUMENTS_MISSING');
    }
    business.verification.status = 'approved';
    business.verification.rejectionReason = undefined;
  } else if (action === 'reject') {
    if (!reason) throw new AppError('Rejection reason required', 422);
    business.verification.status = 'rejected';
    business.verification.rejectionReason = reason;
  } else if (action === 'request_info') {
    if (!reason) throw new AppError('Message required', 422);
    business.verification.status = 'pending';
    business.verification.rejectionReason = reason;
  } else {
    throw new AppError('action must be approve, reject, or request_info', 422);
  }

  business.verification.reviewedBy = adminId;
  business.verification.reviewedAt = new Date();
  await business.save();

  await Notification.create({
    user: business.owner,
    type: 'verification',
    title: action === 'approve' ? 'Business approved 🎉' : action === 'reject' ? 'Verification rejected' : 'More information needed',
    body: action === 'approve'
      ? `${business.name} is now verified and visible to customers.`
      : reason,
    data: { businessId: String(business._id), status: business.verification.status },
  });

  return business;
};

// ---------------------------------------------------------------------------------------------
// Statistics. Everything below is computed from the live database on request — nothing is cached,
// estimated or made up. Days are UTC days. "Revenue" is gross: what customers paid for DELIVERED orders
// (items + delivery fee − discounts). The platform takes no commission today, so there is no "platform revenue".
// ---------------------------------------------------------------------------------------------
const DAY = 24 * 60 * 60 * 1000;
const DAYS = 14;
const dayKey = (d) => new Date(d).toISOString().slice(0, 10);

/** Fills in missing days with zeros so charts always get exactly `days` consecutive points (oldest first). */
exports.fillDays = (rows, days = DAYS, now = new Date(), fields = ['count']) => {
  const byDay = new Map((rows || []).map((r) => [r._id, r]));
  const out = [];
  for (let i = days - 1; i >= 0; i -= 1) {
    const key = dayKey(new Date(now.getTime() - i * DAY));
    const row = byDay.get(key) || {};
    const point = { date: key };
    for (const f of fields) point[f] = row[f] || 0;
    out.push(point);
  }
  return out;
};

const perDay = (field = 'createdAt') => ({ $dateToString: { format: '%Y-%m-%d', date: `$${field}` } });

exports.getStats = async (now = new Date()) => {
  const since = new Date(now.getTime() - (DAYS - 1) * DAY);
  since.setUTCHours(0, 0, 0, 0);
  const d7 = new Date(now.getTime() - 7 * DAY);
  const d30 = new Date(now.getTime() - 30 * DAY);
  const startToday = new Date(now);
  startToday.setUTCHours(0, 0, 0, 0);
  const people = { role: { $nin: ADMIN_ROLES }, deletedAt: null };

  const [
    usersByRole, newUsers7, newUsers30, signupSeries,
    shopsByStatus, shopsWithVideo, shopsOpen,
    ordersByStatus, ordersToday, ordersSeries, payments, needsRefund, topShops,
    reviewAgg, couponAgg, recentOrders,
  ] = await Promise.all([
    User.aggregate([{ $match: people }, { $group: { _id: '$role', n: { $sum: 1 } } }]),
    User.countDocuments({ ...people, createdAt: { $gte: d7 } }),
    User.countDocuments({ ...people, createdAt: { $gte: d30 } }),
    User.aggregate([{ $match: { ...people, createdAt: { $gte: since } } }, { $group: { _id: perDay(), count: { $sum: 1 } } }]),

    Business.aggregate([{ $match: { isActive: true } }, { $group: { _id: '$verification.status', n: { $sum: 1 } } }]),
    Business.countDocuments({ isActive: true, 'verification.status': 'approved', 'promoVideo.review.status': 'approved' }),
    Business.countDocuments({ isActive: true, 'verification.status': 'approved', isOpen: true }),

    Order.aggregate([{ $group: { _id: '$status', n: { $sum: 1 }, amount: { $sum: '$amounts.total' } } }]),
    Order.countDocuments({ createdAt: { $gte: startToday } }),
    Order.aggregate([
      { $match: { createdAt: { $gte: since } } },
      { $group: { _id: perDay(), count: { $sum: 1 }, revenue: { $sum: { $cond: [{ $eq: ['$status', 'delivered'] }, '$amounts.total', 0] } } } },
    ]),
    Order.aggregate([
      { $match: { status: { $nin: ['cancelled', 'rejected', 'payment_failed'] } } },
      { $group: { _id: '$payment.method', n: { $sum: 1 } } },
    ]),
    Order.countDocuments({ 'payment.needsRefund': true }),
    Order.aggregate([
      { $match: { status: 'delivered' } },
      { $group: { _id: '$business', orders: { $sum: 1 }, revenue: { $sum: '$amounts.total' } } },
      { $sort: { revenue: -1 } }, { $limit: 5 },
      { $lookup: { from: 'businesses', localField: '_id', foreignField: '_id', as: 'shop' } },
      { $project: { orders: 1, revenue: 1, name: { $arrayElemAt: ['$shop.name', 0] } } },
    ]),

    Review.aggregate([{ $match: { deletedAt: null } }, { $group: { _id: null, count: { $sum: 1 }, avg: { $avg: '$rating' } } }]),
    Coupon.aggregate([{ $group: { _id: null, total: { $sum: 1 }, active: { $sum: { $cond: ['$isActive', 1, 0] } }, redeemed: { $sum: '$usedCount' } } }]),
    Order.find().sort('-createdAt').limit(8).select('orderNumber status amounts.total payment.method createdAt business').populate('business', 'name'),
  ]);

  const countOf = (rows, key) => (rows || []).find((r) => r._id === key)?.n || 0;
  const delivered = (ordersByStatus || []).find((r) => r._id === 'delivered');
  const ordersTotal = (ordersByStatus || []).reduce((s, r) => s + r.n, 0);
  const activeStatuses = ['pending', 'confirmed', 'preparing', 'ready', 'assigned', 'picked_up', 'out_for_delivery'];
  const rev = (reviewAgg || [])[0];
  const cp = (couponAgg || [])[0];
  const deliveredCount = delivered?.n || 0;
  const deliveredRevenue = delivered?.amount || 0;

  return {
    generatedAt: now.toISOString(),
    users: {
      customers: countOf(usersByRole, 'customer'),
      entrepreneurs: countOf(usersByRole, 'entrepreneur'),
      deliveryPartners: countOf(usersByRole, 'delivery_partner'),
      total: (usersByRole || []).reduce((s, r) => s + r.n, 0),
      newLast7Days: newUsers7,
      newLast30Days: newUsers30,
      signupsByDay: exports.fillDays(signupSeries, DAYS, now),
    },
    shops: {
      approved: countOf(shopsByStatus, 'approved'),
      inReview: countOf(shopsByStatus, 'in_review'),
      pending: countOf(shopsByStatus, 'pending'),
      rejected: countOf(shopsByStatus, 'rejected'),
      openNow: shopsOpen,
      withPromoVideo: shopsWithVideo,
      topByRevenue: (topShops || []).map((t) => ({ id: t._id, name: t.name || 'Unknown shop', orders: t.orders, revenue: t.revenue })),
    },
    orders: {
      total: ordersTotal,
      today: ordersToday,
      active: activeStatuses.reduce((s, k) => s + countOf(ordersByStatus, k), 0),
      delivered: deliveredCount,
      cancelled: countOf(ordersByStatus, 'cancelled') + countOf(ordersByStatus, 'rejected'),
      byStatus: Object.fromEntries((ordersByStatus || []).map((r) => [r._id, r.n])),
      revenueDelivered: deliveredRevenue,
      averageOrderValue: deliveredCount ? Math.round(deliveredRevenue / deliveredCount) : 0,
      byPaymentMethod: Object.fromEntries((payments || []).map((r) => [r._id || 'unknown', r.n])),
      needsRefund,
      byDay: exports.fillDays(ordersSeries, DAYS, now, ['count', 'revenue']),
      recent: (recentOrders || []).map((o) => ({
        id: o._id, orderNumber: o.orderNumber, status: o.status, total: o.amounts?.total || 0,
        shop: o.business?.name || '', method: o.payment?.method, createdAt: o.createdAt,
      })),
    },
    reviews: { count: rev?.count || 0, average: rev ? Math.round(rev.avg * 10) / 10 : 0 },
    coupons: { total: cp?.total || 0, active: cp?.active || 0, redeemed: cp?.redeemed || 0 },
  };
};

/** Read-only member list for the admin. Admin accounts are never listed. */
exports.listUsers = async ({ role, q, page, limit } = {}) => {
  const p = parsePage({ page, limit }, { defLimit: 20, maxLimit: 100 });
  const filter = { role: { $nin: ADMIN_ROLES }, deletedAt: null };
  if (role) filter.role = role;
  if (q) {
    const rx = new RegExp(escapeRegex(String(q).trim().slice(0, 60)), 'i');
    filter.$or = [{ name: rx }, { email: rx }];
  }
  const [items, total] = await Promise.all([
    User.find(filter).sort('-createdAt').skip(p.skip).limit(p.limit).select('name email phone role isActive avatarUrl createdAt'),
    User.countDocuments(filter),
  ]);
  return { items, meta: { page: p.page, limit: p.limit, total } };
};

const cleanReason = (r) => String(r ?? '').trim().slice(0, 300);

// Tell the person in the app AND by email. Neither can fail the admin's action.
async function tell(userId, to, { title, body, kind, data }) {
  await notifications.notify(userId, { type: 'system', title, body, data: { kind, ...data } });
  const mail = await email.sendNoticeEmail({ to, subject: title, heading: title, message: body });
  return { inApp: true, email: !!mail?.sent };
}

/** Suspend or restore a member. A reason is required to suspend. Suspending signs them out everywhere and hides
 *  their shops; restoring brings back only the shops that were hidden because of this account. The administrator
 *  cannot be suspended. Asking for the state the member is already in does nothing (no duplicate notices). */
exports.setUserActive = async (userId, isActive, { reason } = {}) => {
  const user = await User.findById(userId);
  if (!user || user.deletedAt) throw new AppError('User not found', 404);
  if (ADMIN_ROLES.includes(user.role)) throw new AppError('The administrator account cannot be changed here', 403);
  const next = !!isActive;
  const why = cleanReason(reason);
  if (!next && why.length < 3) throw new AppError('Give a reason for the suspension', 422);
  if (next === (user.isActive !== false)) return { id: user._id, isActive: next, changed: false };

  user.isActive = next;
  user.suspension = next ? undefined : { reason: why, at: new Date() };
  await user.save();
  if (!next) {
    await RefreshSession.deleteMany({ user: user._id });
    await Business.updateMany({ owner: user._id, isActive: true, deletedAt: null },
      { $set: { isActive: false, suspension: { reason: 'The owner account is suspended', at: new Date(), byOwner: true } } });
  } else {
    await Business.updateMany({ owner: user._id, 'suspension.byOwner': true }, { $set: { isActive: true }, $unset: { suspension: 1 } });
  }
  const notified = await tell(user._id, user.email, next
    ? { title: 'Your account was restored', body: 'Your account is active again. You can sign in now.', kind: 'account_restored' }
    : { title: 'Your account was suspended', body: `Your account has been suspended.\nReason: ${why}\nIf you think this is a mistake, please contact support.`, kind: 'account_suspended' });
  return { id: user._id, isActive: next, changed: true, notified };
};

/** Suspend or restore ONE shop (it disappears from customers while suspended). Reason required to suspend. */
exports.setBusinessActive = async (businessId, isActive, { reason } = {}) => {
  const business = await Business.findOne({ _id: businessId, deletedAt: null });
  if (!business) throw new AppError('Business not found', 404);
  const next = !!isActive;
  const why = cleanReason(reason);
  if (!next && why.length < 3) throw new AppError('Give a reason for the suspension', 422);
  if (next === (business.isActive !== false)) return { id: business._id, isActive: next, changed: false };
  const owner = await User.findById(business.owner).select('email isActive');
  if (next && owner && owner.isActive === false) {
    throw new AppError("The owner's account is suspended. Restore the account first.", 409, 'OWNER_SUSPENDED');
  }
  business.isActive = next;
  business.suspension = next ? undefined : { reason: why, at: new Date(), byOwner: false };
  await business.save();
  const notified = await tell(business.owner, owner?.email, next
    ? { title: `${business.name} was restored`, body: `${business.name} is visible to customers again.`, kind: 'shop_restored', data: { businessId: String(business._id) } }
    : { title: `${business.name} was suspended`, body: `${business.name} is hidden from customers.\nReason: ${why}\nIf you think this is a mistake, please contact support.`, kind: 'shop_suspended', data: { businessId: String(business._id) } });
  return { id: business._id, isActive: next, changed: true, notified };
};
