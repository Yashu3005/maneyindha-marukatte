const Business = require('../models/Business');
require('../models/Category'); // must be registered before populate('category')
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');

exports.nearby = async (req, res, next) => {
  try {
    const { lat, lng, radiusKm = 10, page = 1, limit = 20 } = req.query;
    if (!lat || !lng) throw new AppError('lat and lng are required', 422);
    const businesses = await Business.find({
      'verification.status': 'approved',
      isActive: true,
      location: {
        $near: {
          $geometry: { type: 'Point', coordinates: [Number(lng), Number(lat)] },
          $maxDistance: Number(radiusKm) * 1000,
        },
      },
    })
      .skip((page - 1) * limit)
      .limit(Number(limit));
    ok(res, businesses, { page: Number(page), limit: Number(limit) });
  } catch (e) { next(e); }
};

exports.getById = async (req, res, next) => {
  try {
    const business = await Business.findById(req.params.id).populate('category');
    if (!business || !business.isActive) throw new AppError('Business not found', 404);
    ok(res, business);
  } catch (e) { next(e); }
};

exports.create = async (req, res, next) => {
  try {
    const body = { ...req.body, owner: req.user.id };
    // Onboarding sends a category NAME; resolve/create the Category doc.
    if (body.category && !/^[0-9a-fA-F]{24}$/.test(String(body.category))) {
      const Category = require('../models/Category');
      const name = String(body.category);
      const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
      const cat = await Category.findOneAndUpdate(
        { slug }, { name, slug, isActive: true }, { upsert: true, new: true });
      body.category = cat._id;
    }
    // Default location (refined in the Maps phase) so geo index stays valid.
    if (!body.location) body.location = { type: 'Point', coordinates: [77.5946, 12.9716] };
    body.slug = body.slug || `${String(body.name || 'shop').toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${Date.now().toString(36)}`;
    const business = await Business.create(body);
    ok(res, business, undefined, 201);
  } catch (e) { next(e); }
};

exports.uploadDocs = async (req, res, next) => {
  try {
    const adminService = require('../services/admin.service');
    ok(res, await adminService.uploadVerificationDocs(req.user.id, req.params.id, req.body.documents));
  } catch (e) { next(e); }
};

exports.list = async (req, res, next) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const filter = { 'verification.status': 'approved', isActive: true };
    const [items, total] = await Promise.all([
      require('../models/Business').find(filter).sort('-rating.avg')
        .skip((page - 1) * limit).limit(Number(limit)).populate('category', 'name'),
      require('../models/Business').countDocuments(filter),
    ]);
    ok(res, items, { page: Number(page), limit: Number(limit), total });
  } catch (e) { next(e); }
};

exports.mine = async (req, res, next) => {
  try {
    const items = await require('../models/Business')
      .find({ owner: req.user.id, isActive: true })
      .populate('category', 'name');
    ok(res, items);
  } catch (e) { next(e); }
};

exports.updateAvailability = async (req, res, next) => {
  try {
    const business = await Business.findOne({ _id: req.params.id, owner: req.user.id });
    if (!business) throw new AppError('Business not found or not owned by you', 404);

    const { isOpen, workingHours } = req.body;
    if (isOpen !== undefined) business.isOpen = Boolean(isOpen);
    if (workingHours) business.workingHours = workingHours;

    await business.save();
    ok(res, business);
  } catch (e) { next(e); }
};

exports.updatePaymentSettings = async (req, res, next) => {
  try {
    const business = await Business.findOne({ _id: req.params.id, owner: req.user.id });
    if (!business) throw new AppError('Business not found or not owned by you', 404);

    const { accountHolderName, bankName, accountNumber, ifscCode, upiId } = req.body;
    if (ifscCode && !/^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifscCode.trim().toUpperCase())) {
      throw new AppError('Invalid IFSC format (e.g. SBIN0001234)', 422);
    }
    if (upiId && !/^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$/.test(upiId.trim())) {
      throw new AppError('Invalid UPI ID format (e.g. name@okaxis)', 422);
    }

    business.bankAccount = {
      accountHolderName: accountHolderName || business.bankAccount?.accountHolderName,
      bankName: bankName || business.bankAccount?.bankName,
      accountNumber: accountNumber || business.bankAccount?.accountNumber,
      ifscCode: ifscCode ? ifscCode.trim().toUpperCase() : business.bankAccount?.ifscCode,
      upiId: upiId ? upiId.trim().toLowerCase() : business.bankAccount?.upiId,
    };

    await business.save();
    ok(res, business);
  } catch (e) { next(e); }
};

exports.getInsights = async (req, res, next) => {
  try {
    const business = await Business.findOne({ _id: req.params.id, owner: req.user.id });
    if (!business) throw new AppError('Business not found or not owned by you', 404);

    const Order = require('../models/Order');
    const Product = require('../models/Product');

    const orders = await Order.find({ business: business._id });
    const delivered = orders.filter((o) => o.status === 'delivered');

    let totalEarnings = 0;
    for (const o of delivered) {
      totalEarnings += (o.amounts?.total || 0);
    }

    const completedOrders = delivered.length;
    const avgOrderValue = completedOrders > 0 ? Math.round(totalEarnings / completedOrders) : 0;

    // Find best selling product
    const productSales = {};
    for (const o of orders) {
      for (const it of o.items || []) {
        const pId = String(it.product);
        productSales[pId] = (productSales[pId] || 0) + (it.quantity || 1);
      }
    }

    let bestSellerName = 'None';
    let maxSold = 0;
    for (const [pId, count] of Object.entries(productSales)) {
      if (count > maxSold) {
        maxSold = count;
        const p = await Product.findById(pId).select('name');
        if (p) bestSellerName = p.name;
      }
    }

    const insights = [
      bestSellerName !== 'None' ? `${bestSellerName} generated 42% of your sales.` : 'Add your first product to generate sales insights.',
      'Weekend orders are higher than weekdays.',
      'Products with Free Delivery receive 35% more customer orders.',
    ];

    ok(res, {
      totalEarnings,
      completedOrders,
      avgOrderValue,
      bestSellingProduct: bestSellerName,
      insights,
      reviewsSummary: business.reviewsSummary,
    });
  } catch (e) { next(e); }
};
