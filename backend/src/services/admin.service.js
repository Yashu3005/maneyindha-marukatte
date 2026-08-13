const Business = require('../models/Business');
const Notification = require('../models/Notification');
const AppError = require('../utils/AppError');

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

exports.reviewBusiness = async (adminId, businessId, { action, reason }) => {
  const business = await Business.findById(businessId);
  if (!business) throw new AppError('Business not found', 404);

  if (!['pending', 'in_review'].includes(business.verification.status)) {
    throw new AppError(`Business is already ${business.verification.status}`, 422);
  }

  if (action === 'approve') {
    business.verification.status = 'approved';
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

exports.uploadVerificationDocs = async (ownerId, businessId, documents) => {
  const business = await Business.findOne({ _id: businessId, owner: ownerId });
  if (!business) throw new AppError('Business not found', 404);

  business.verification.documents.push(
    ...documents.map((d) => ({ ...d, uploadedAt: new Date() }))
  );
  business.verification.status = 'in_review';
  await business.save();
  return business;
};

exports.stats = async () => {
  const User = require('../models/User');
  const Order = require('../models/Order');
  const Product = require('../models/Product');
  const [customers, entrepreneurs, businesses, approved, orders, products, revenueAgg] =
    await Promise.all([
      User.countDocuments({ role: 'customer', isActive: true }),
      User.countDocuments({ role: 'entrepreneur', isActive: true }),
      Business.countDocuments({ isActive: true }),
      Business.countDocuments({ 'verification.status': 'approved', isActive: true }),
      Order.countDocuments({}),
      Product.countDocuments({ isActive: true }),
      Order.aggregate([
        { $match: { status: 'delivered' } },
        { $group: { _id: null, total: { $sum: '$amounts.total' } } },
      ]),
    ]);
  return {
    customers, entrepreneurs, businesses, approved, orders, products,
    revenue: revenueAgg[0]?.total || 0,
  };
};

exports.setUserActive = async (userId, isActive) => {
  const User = require('../models/User');
  const user = await User.findById(userId);
  if (!user) throw new AppError('User not found', 404);
  if (['admin', 'super_admin'].includes(user.role)) {
    throw new AppError('Cannot block an admin account', 403);
  }
  user.isActive = isActive;
  await user.save();
  return { id: user._id, isActive: user.isActive };
};
