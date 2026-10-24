const crypto = require('crypto');
const SupportTicket = require('../models/SupportTicket');
const { ok } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');

exports.create = async (req, res, next) => {
  try {
    const { issueType, description, orderId, attachments } = req.body;
    if (!issueType || !description) throw new AppError('issueType and description are required', 422);

    const ticketNumber = `SUP${Date.now().toString().slice(-4)}${crypto.randomInt(10, 99)}`;
    const ticket = await SupportTicket.create({
      ticketNumber,
      customer: req.user.id,
      issueType,
      description,
      order: orderId || undefined,
      attachments: attachments || [],
    });

    ok(res, ticket, undefined, 201);
  } catch (e) {
    next(e);
  }
};

exports.myTickets = async (req, res, next) => {
  try {
    const tickets = await SupportTicket.find({ customer: req.user.id })
      .sort('-createdAt')
      .populate('order', 'orderNumber status');
    ok(res, tickets);
  } catch (e) {
    next(e);
  }
};

exports.adminList = async (req, res, next) => {
  try {
    const { status, type } = req.query;
    const filter = {};
    if (status && status !== 'all') filter.status = status;
    if (type === 'refund') filter.issueType = 'Refund Appeal';
    else if (type === 'replacement') filter.issueType = 'Replacement Appeal';
    else if (type === 'general') filter.issueType = { $nin: ['Refund Appeal', 'Replacement Appeal'] };

    const tickets = await SupportTicket.find(filter)
      .sort('-createdAt')
      .populate('customer', 'name email phone')
      .populate('order', 'orderNumber status business items amounts');
    ok(res, tickets);
  } catch (e) {
    next(e);
  }
};

exports.adminUpdate = async (req, res, next) => {
  try {
    const { status, adminNotes } = req.body;
    const ticket = await SupportTicket.findById(req.params.id);
    if (!ticket) throw new AppError('Ticket not found', 404);

    if (status) ticket.status = status;
    if (adminNotes !== undefined) ticket.adminNotes = adminNotes;
    if (status === 'resolved' || status === 'closed') {
      ticket.resolvedBy = req.user.id;
      ticket.resolvedAt = new Date();
    }

    await ticket.save();
    ok(res, ticket);
  } catch (e) {
    next(e);
  }
};
