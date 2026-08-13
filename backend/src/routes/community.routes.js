const router = require('express').Router();
const Joi = require('joi');
const { requireAuth, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const CommunityPost = require('../models/CommunityPost');
const Business = require('../models/Business');
const AppError = require('../utils/AppError');
const { ok } = require('../utils/apiResponse');

router.get('/', async (req, res, next) => {
  try {
    const items = await CommunityPost.find({})
      .sort('-createdAt').limit(30)
      .populate('business', 'name logoUrl')
      .populate('author', 'name');
    ok(res, items);
  } catch (e) { next(e); }
});

router.post('/',
  requireAuth, requireRole('entrepreneur'),
  validate(Joi.object({
    caption: Joi.string().max(500).required(),
    image: Joi.string().uri(),
  })),
  async (req, res, next) => {
    try {
      const business = await Business.findOne({ owner: req.user.id, isActive: true });
      if (!business) throw new AppError('Set up your business first', 422);
      const post = await CommunityPost.create({
        author: req.user.id, business: business._id,
        caption: req.body.caption, image: req.body.image,
      });
      ok(res, post, undefined, 201);
    } catch (e) { next(e); }
  });

router.post('/:id/like', requireAuth, async (req, res, next) => {
  try {
    const post = await CommunityPost.findById(req.params.id);
    if (!post) throw new AppError('Post not found', 404);
    const idx = post.likes.findIndex((u) => String(u) === String(req.user.id));
    if (idx >= 0) post.likes.splice(idx, 1); else post.likes.push(req.user.id);
    await post.save();
    ok(res, { liked: idx < 0, count: post.likes.length });
  } catch (e) { next(e); }
});

module.exports = router;
