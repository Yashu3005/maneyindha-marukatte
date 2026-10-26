const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const Order = require('../models/Order');
const Business = require('../models/Business');

let io;

const ADMIN_ROLES = ['admin', 'super_admin'];
const ORDER_ROOM = /^order:([0-9a-fA-F]{24})$/;

// A socket may join only rooms it is entitled to:
//   user:<own id>   — personal notifications
//   order:<id>      — live tracking, for the order's customer / shop owner / partner / admins
// Anything else (including chat:* — no chat model exists yet) is refused.
async function canJoin(user, room) {
  if (typeof room !== 'string') return false;
  if (room === `user:${user.id}`) return true;
  const m = ORDER_ROOM.exec(room);
  if (!m) return false;
  if (ADMIN_ROLES.includes(user.role)) return true;
  const order = await Order.findById(m[1]).select('customer business deliveryPartner');
  if (!order) return false;
  if (String(order.customer) === String(user.id)) return true;
  if (order.deliveryPartner && String(order.deliveryPartner) === String(user.id)) return true;
  return !!(await Business.exists({ _id: order.business, owner: user.id }));
}

function initSocket(server) {
  const origins = process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',').map((o) => o.trim()) : '*';
  io = new Server(server, { cors: { origin: origins } });

  // Same JWT as the REST API; unauthenticated sockets are rejected at handshake.
  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('Authentication required'));
    try {
      socket.user = jwt.verify(token, process.env.JWT_SECRET);
      next();
    } catch {
      next(new Error('Invalid or expired token'));
    }
  });

  io.on('connection', (socket) => {
    socket.on('join', async (room, ack) => {
      let allowed = false;
      try { allowed = await canJoin(socket.user, room); } catch { allowed = false; }
      if (allowed) socket.join(room);
      if (typeof ack === 'function') ack({ joined: allowed });
    });
  });
  return io;
}

const getIO = () => io;
module.exports = { initSocket, getIO, canJoin };
