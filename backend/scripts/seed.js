/* Seed dev data: admin, entrepreneur, categories, approved businesses, products, coupon.
   Usage: npm run seed  (wipes and re-creates seed data, dev only) */
require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const User = require('../src/models/User');
const Business = require('../src/models/Business');
const Product = require('../src/models/Product');
const Category = require('../src/models/Category');
const Coupon = require('../src/models/Coupon');

const BLR = (lng, lat) => ({ type: 'Point', coordinates: [lng, lat] });

async function run() {
  await mongoose.connect(process.env.MONGODB_URI);
  console.log('Connected. Seeding...');

  await Promise.all([
    User.deleteMany({ email: { $in: ['admin@mm.dev', 'asha@mm.dev', 'customer@mm.dev'] } }),
    Business.deleteMany({ slug: { $in: ['ashas-home-bakes', 'kala-crafts', 'ruchi-tiffins'] } }),
    Coupon.deleteMany({ code: 'WELCOME10' }),
  ]);

  const hash = await bcrypt.hash('password123', 12);
  const [admin, asha, customer] = await User.create([
    { name: 'Admin', email: 'admin@mm.dev', passwordHash: hash, role: 'admin' },
    { name: 'Asha', email: 'asha@mm.dev', passwordHash: hash, role: 'entrepreneur' },
    { name: 'Priya', email: 'customer@mm.dev', passwordHash: hash, role: 'customer' },
  ]);

  const catNames = ['Baking', 'Handicrafts', 'Tiffin & Meals', 'Boutique', 'Home Decor'];
  const cats = {};
  for (const name of catNames) {
    const slug = name.toLowerCase().replace(/[^a-z]+/g, '-');
    cats[name] = await Category.findOneAndUpdate(
      { slug }, { name, slug, isActive: true }, { upsert: true, new: true }
    );
  }

  const approved = { status: 'approved', reviewedAt: new Date() };
  const [bakery, crafts, tiffin] = await Business.create([
    {
      owner: asha._id, name: "Asha's Home Bakes", slug: 'ashas-home-bakes',
      description: 'Fresh homemade cakes, cookies and brownies baked with love in Jayanagar.',
      category: cats['Baking']._id, location: BLR(77.5946, 12.9250),
      address: { line1: '4th Block', city: 'Bengaluru', state: 'KA', pincode: '560011' },
      verification: approved, isOpen: true,
      logoUrl: 'https://picsum.photos/seed/bakery/200',
      bannerUrl: 'https://picsum.photos/seed/bakerybanner/800/300',
    },
    {
      owner: asha._id, name: 'Kala Crafts', slug: 'kala-crafts',
      description: 'Handmade jewelry, crochet and embroidery pieces.',
      category: cats['Handicrafts']._id, location: BLR(77.6408, 12.9716),
      address: { line1: 'Indiranagar', city: 'Bengaluru', state: 'KA', pincode: '560038' },
      verification: approved, isOpen: true,
      logoUrl: 'https://picsum.photos/seed/crafts/200',
      bannerUrl: 'https://picsum.photos/seed/craftsbanner/800/300',
    },
    {
      owner: asha._id, name: 'Ruchi Tiffins', slug: 'ruchi-tiffins',
      description: 'Daily home-cooked tiffins and festive sweets.',
      category: cats['Tiffin & Meals']._id, location: BLR(77.5806, 12.9352),
      address: { line1: 'Basavanagudi', city: 'Bengaluru', state: 'KA', pincode: '560004' },
      verification: approved, isOpen: true,
      logoUrl: 'https://picsum.photos/seed/tiffin/200',
      bannerUrl: 'https://picsum.photos/seed/tiffinbanner/800/300',
    },
  ]);

  const P = (business, name, price, cat, seed, stock = 25) => ({
    business, name, price, category: cats[cat]._id, stock,
    description: `${name} — made fresh to order.`,
    images: [`https://picsum.photos/seed/${seed}/400/300`],
    isActive: true,
  });

  await Product.create([
    P(bakery._id, 'Chocolate Truffle Cake (500g)', 549, 'Baking', 'cake1'),
    P(bakery._id, 'Butter Cookies Box (250g)', 199, 'Baking', 'cookies'),
    P(bakery._id, 'Walnut Brownies (6 pc)', 299, 'Baking', 'brownies'),
    P(bakery._id, 'Red Velvet Cupcakes (4 pc)', 249, 'Baking', 'cupcake'),
    P(crafts._id, 'Handmade Terracotta Earrings', 349, 'Handicrafts', 'earrings'),
    P(crafts._id, 'Crochet Tote Bag', 799, 'Handicrafts', 'tote'),
    P(crafts._id, 'Embroidered Cushion Cover', 449, 'Handicrafts', 'cushion'),
    P(tiffin._id, 'Veg Thali Tiffin', 129, 'Tiffin & Meals', 'thali', 50),
    P(tiffin._id, 'Bisi Bele Bath (1 box)', 99, 'Tiffin & Meals', 'bbb', 50),
    P(tiffin._id, 'Festive Sweets Box (500g)', 399, 'Tiffin & Meals', 'sweets'),
  ]);

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
