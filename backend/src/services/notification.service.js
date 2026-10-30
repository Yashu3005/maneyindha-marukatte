const Notification = require('../models/Notification');
const logger = require('../utils/logger');

// Saving a notification must never break the action that caused it.
exports.notify = async (userId, { type = 'system', title, body, data }) => {
  try {
    return await Notification.create({ user: userId, type, title, body, data });
  } catch (e) {
    logger.warn(`Notification not saved: ${e?.message}`);
    return null;
  }
};

exports.listFor = async (userId) => {
  const [items, unread] = await Promise.all([
    Notification.find({ user: userId }).sort('-createdAt').limit(50).select('type title body data isRead createdAt'),
    Notification.countDocuments({ user: userId, isRead: false }),
  ]);
  return { items, unread };
};

// Only ever touches the caller's own notifications.
exports.markRead = async (userId, ids) => {
  const filter = { user: userId, isRead: false };
  if (Array.isArray(ids) && ids.length) filter._id = { $in: ids };
  const r = await Notification.updateMany(filter, { $set: { isRead: true } });
  return { updated: r?.modifiedCount ?? 0 };
};
