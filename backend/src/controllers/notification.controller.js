const Notification = require('../models/Notification');
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');

exports.list = async (req, res, next) => {
  try {
    const items = await Notification.find({ user: req.user.id })
      .sort('-createdAt')
      .limit(50);
    const unreadCount = await Notification.countDocuments({ user: req.user.id, isRead: false });
    ok(res, { items, unreadCount });
  } catch (e) {
    next(e);
  }
};

exports.markRead = async (req, res, next) => {
  try {
    const notification = await Notification.findOneAndUpdate(
      { _id: req.params.id, user: req.user.id },
      { isRead: true },
      { new: true }
    );
    if (!notification) throw new AppError('Notification not found', 404);
    ok(res, notification);
  } catch (e) {
    next(e);
  }
};

exports.remove = async (req, res, next) => {
  try {
    const result = await Notification.findOneAndDelete({
      _id: req.params.id,
      user: req.user.id,
    });
    if (!result) throw new AppError('Notification not found', 404);
    ok(res, { deleted: true });
  } catch (e) {
    next(e);
  }
};

exports.clearAll = async (req, res, next) => {
  try {
    await Notification.deleteMany({ user: req.user.id });
    ok(res, { cleared: true });
  } catch (e) {
    next(e);
  }
};
