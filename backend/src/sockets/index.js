const { Server } = require('socket.io');
let io;

function initSocket(server) {
  io = new Server(server, { cors: { origin: '*' } });
  io.on('connection', (socket) => {
    // Rooms: order:<id> for live tracking, chat:<id> for messaging
    socket.on('join', (room) => socket.join(room));
  });
  return io;
}

const getIO = () => io;
module.exports = { initSocket, getIO };
