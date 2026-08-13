const router = require('express').Router();
const { ok } = require('../utils/apiResponse');

// GET /images?q=cake&count=6 — Pexels when PEXELS_API_KEY is set, placeholder otherwise.
router.get('/', async (req, res, next) => {
  const q = (req.query.q || 'handmade craft').toString().slice(0, 60);
  const count = Math.min(Number(req.query.count) || 6, 12);
  try {
    if (process.env.PEXELS_API_KEY) {
      const r = await fetch(
        `https://api.pexels.com/v1/search?query=${encodeURIComponent(q)}&per_page=${count}`,
        { headers: { Authorization: process.env.PEXELS_API_KEY } }
      );
      if (r.ok) {
        const data = await r.json();
        const urls = (data.photos || []).map((p) => p.src.medium);
        if (urls.length) return ok(res, urls);
      }
    }
    ok(res, Array.from({ length: count }, (_, i) =>
      `https://picsum.photos/seed/${encodeURIComponent(q)}-${i}/400/400`));
  } catch (e) { next(e); }
});

module.exports = router;
