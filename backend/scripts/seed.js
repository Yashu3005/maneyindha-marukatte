/* Seed dev data with Pexels photos when PEXELS_API_KEY is set.
   Usage: npm run seed */
require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const User = require('../src/models/User');
const Business = require('../src/models/Business');
const Product = require('../src/models/Product');
const Category = require('../src/models/Category');
const Coupon = require('../src/models/Coupon');

const BLR = (lng, lat) => ({ type: 'Point', coordinates: [lng, lat] });
const PEXELS = process.env.PEXELS_API_KEY;

const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

async function pexelsOne(query) {
  const r = await fetch(
    `https://api.pexels.com/v1/search?query=${encodeURIComponent(query)}&per_page=1&orientation=landscape`,
    { headers: { Authorization: PEXELS } }
  );
  if (r.status === 429) {           // rate limited: wait once and retry
    await sleep(1500);
    return pexelsOne(query);
  }
  if (!r.ok) {
    console.log(`    pexels ${r.status} for "${query}"`);
    return null;
  }
  const d = await r.json();
  return (d.photos && d.photos[0] && d.photos[0].src && d.photos[0].src.large) || null;
}

// Tries the specific query first, then a broader fallback, then a placeholder.
async function img(query, fallbackQuery, seedName, w = 640, h = 420) {
  if (PEXELS) {
    try {
      await sleep(300); // stay under Pexels burst limits
      let u = await pexelsOne(query);
      if (!u) {
        console.log(`    no result for "${query}", trying "${fallbackQuery}"`);
        u = await pexelsOne(fallbackQuery);
      }
      if (u) return u;
      console.log(`    PLACEHOLDER used for "${query}"`);
    } catch (e) {
      console.log(`    pexels error for "${query}": ${e.message} — PLACEHOLDER used`);
    }
  } else {
    console.log('    (no PEXELS_API_KEY — placeholders in use)');
  }
  return `https://picsum.photos/seed/${seedName}/${w}/${h}`;
}

async function run() {
  await mongoose.connect(process.env.MONGODB_URI);
  console.log('Connected. Seeding' + (PEXELS ? ' with Pexels photos…' : ' with placeholders…'));

  const oldShops = await Business.find(
    { slug: { $in: ['ashas-home-bakes', 'kala-crafts', 'ruchi-tiffins'] } }).select('_id');
  await Promise.all([
    User.deleteMany({ email: { $in: ['admin@mm.dev', 'asha@mm.dev', 'customer@mm.dev'] } }),
    Product.deleteMany({ business: { $in: oldShops.map((b) => b._id) } }),
    Business.deleteMany({ slug: { $in: ['ashas-home-bakes', 'kala-crafts', 'ruchi-tiffins'] } }),
    Coupon.deleteMany({ code: 'WELCOME10' }),
  ]);

  const hash = await bcrypt.hash('password123', 12);
  const [, asha] = await User.create([
    { name: 'Admin', email: 'admin@mm.dev', passwordHash: hash, role: 'admin', profileComplete: true },
    { name: 'Asha', email: 'asha@mm.dev', passwordHash: hash, role: 'entrepreneur', profileComplete: true },
    { name: 'Priya', email: 'customer@mm.dev', passwordHash: hash, role: 'customer', profileComplete: true },
  ]);

  const catNames = ['Baking', 'Handicrafts', 'Tiffin & Meals', 'Boutique', 'Home Decor'];
  const cats = {};
  for (const name of catNames) {
    const slug = name.toLowerCase().replace(/[^a-z]+/g, '-');
    cats[name] = await Category.findOneAndUpdate(
      { slug }, { name, slug, isActive: true }, { upsert: true, new: true });
  }

  const approved = { status: 'approved', reviewedAt: new Date() };

  const shopSpecs = [
    { name: "Asha's Home Bakes", slug: 'ashas-home-bakes', cat: 'Baking',
      desc: 'Fresh homemade cakes, cookies and brownies baked with love in Jayanagar.',
      photo: 'home bakery cakes', fallback: 'bakery', loc: BLR(77.5946, 12.9250), line1: '4th Block, Jayanagar' },
    { name: 'Kala Crafts', slug: 'kala-crafts', cat: 'Handicrafts',
      desc: 'Handmade jewelry, crochet and embroidery pieces.',
      photo: 'handmade crafts jewelry', fallback: 'handicraft', loc: BLR(77.6408, 12.9716), line1: 'Indiranagar' },
    { name: 'Ruchi Tiffins', slug: 'ruchi-tiffins', cat: 'Tiffin & Meals',
      desc: 'Daily home-cooked tiffins and festive sweets.',
      photo: 'indian home food thali', fallback: 'indian food', loc: BLR(77.5806, 12.9352), line1: 'Basavanagudi' },
  ];

  const shops = {};
  for (const s of shopSpecs) {
    shops[s.slug] = await Business.create({
      owner: asha._id, name: s.name, slug: s.slug, description: s.desc,
      category: cats[s.cat]._id, location: s.loc,
      address: { line1: s.line1, city: 'Bengaluru', state: 'KA', pincode: '560011' },
      verification: approved, isOpen: true,
      logoUrl: await img(s.photo, s.fallback, `${s.slug}-logo`, 300, 300),
      bannerUrl: await img(s.photo, s.fallback, `${s.slug}-banner`, 800, 400),
    });
    console.log('  shop:', s.name);
  }

  const productSpecs = [
    ['ashas-home-bakes', 'Chocolate Truffle Cake (500g)', 549, 'Baking', 'chocolate truffle cake', 'chocolate cake'],
    ['ashas-home-bakes', 'Butter Cookies Box (250g)', 199, 'Baking', 'butter cookies', 'cookies'],
    ['ashas-home-bakes', 'Walnut Brownies (6 pc)', 299, 'Baking', 'walnut brownies', 'brownies'],
    ['ashas-home-bakes', 'Red Velvet Cupcakes (4 pc)', 249, 'Baking', 'red velvet cupcakes', 'cupcakes'],
    ['kala-crafts', 'Handmade Terracotta Earrings', 349, 'Handicrafts', 'terracotta earrings', 'earrings'],
    ['kala-crafts', 'Crochet Tote Bag', 799, 'Handicrafts', 'crochet tote bag', 'crochet bag'],
    ['kala-crafts', 'Embroidered Cushion Cover', 449, 'Handicrafts', 'embroidered cushion', 'cushion pillow'],
    ['ruchi-tiffins', 'Veg Thali Tiffin', 129, 'Tiffin & Meals', 'indian thali food', 'indian food plate'],
    ['ruchi-tiffins', 'Bisi Bele Bath (1 box)', 99, 'Tiffin & Meals', 'south indian rice dish', 'indian rice food'],
    ['ruchi-tiffins', 'Festive Sweets Box (500g)', 399, 'Tiffin & Meals', 'indian sweets mithai', 'indian dessert'],
  ];

  for (const [slug, name, price, cat, photo, fallback] of productSpecs) {
    await Product.create({
      business: shops[slug]._id, name, price, category: cats[cat]._id,
      stock: 30, description: `${name} — made fresh to order.`,
      images: [await img(photo, fallback, name.toLowerCase().replace(/[^a-z]+/g, '-'))],
      isActive: true,
    });
    console.log('  product:', name);
  }

  await Coupon.create({
    code: 'WELCOME10', type: 'percent', value: 10, maxDiscount: 100,
    minOrderAmount: 199, usageLimitPerUser: 1, isActive: true,
  });

  console.log(`
Seed complete.
  admin@mm.dev / password123      (admin)
  asha@mm.dev / password123       (entrepreneur)
  customer@mm.dev / password123   (customer)
  Coupon: WELCOME10 (10% off, min ₹199)
`);
  await mongoose.disconnect();
}

run().catch((e) => { console.error(e); process.exit(1); });
