const mongoose = require('mongoose');

const postSchema = new mongoose.Schema(
  {
    author: { type: mongoose.Types.ObjectId, ref: 'User', required: true },
    business: { type: mongoose.Types.ObjectId, ref: 'Business', required: true, index: true },
    image: String,
    caption: { type: String, maxlength: 500 },
    likes: [{ type: mongoose.Types.ObjectId, ref: 'User' }],
  },
  { timestamps: true }
);

module.exports = mongoose.model('CommunityPost', postSchema);
