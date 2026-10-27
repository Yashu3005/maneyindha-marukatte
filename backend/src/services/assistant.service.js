const Business = require('../models/Business');
const Product = require('../models/Product');
const Order = require('../models/Order');
const ai = require('../ai');
const rewards = require('./rewards.service');

const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const STOP = new Set(['the', 'and', 'for', 'with', 'you', 'can', 'any', 'want', 'need', 'how', 'what', 'where', 'show', 'give', 'some',
  'please', 'near', 'nearby', 'shop', 'shops', 'product', 'products', 'have', 'there', 'this', 'that', 'from', 'about', 'which', 'order']);
const ORDER_WORDS = /\b(order|orders|delivery|deliver|track|tracking|status|cancel|refund|late|where is)\b/i;

const GUIDE = [
  'Signing in: customers sign in with a 6-digit code sent to their email.',
  'Finding shops: the Home screen lists approved shops and products. "Near me" uses the phone location only after the customer allows it. Shops can be filtered by category, rating, open now, shops with a video, and sorted by nearest, rating or newest.',
  'Shop videos: some shops show a short video about their products when you open their page.',
  'Cart: a cart holds items from one shop; adding from a different shop replaces the cart.',
  'Checkout: delivery costs Rs 30; self-pickup is free. Payment is cash on delivery or online where online payment is offered.',
  `Rewards: ${rewards.PROGRAMME.map((p) => `${p.code} - ${p.description}`).join('; ')}. Enter the code in the cart. The Rewards screen shows which ones are unlocked.`,
  `Badges: ${rewards.TIERS.map((t) => `${t.label} (${t.min}+ delivered orders)`).join(', ')}.`,
  'Orders: the Orders tab shows each order and its status. A customer can cancel only while the order is pending or confirmed.',
  'Ratings: after an order is delivered, the customer can rate the products; only real buyers can rate.',
  'Becoming a seller: Profile > Become an Entrepreneur, fill shop details, upload ID proof and business proof, then wait for the admin to approve the application. Shops are visible to customers only after approval.',
].join('\n');

function keywords(message) {
  return [...new Set(String(message).toLowerCase().match(/[\p{L}\p{N}]{3,}/gu) || [])].filter((w) => !STOP.has(w)).slice(0, 5);
}

/** Builds the (public) catalogue snippet and, when relevant, the customer's own recent order statuses. */
async function buildContext(userId, message) {
  const words = keywords(message);
  const rx = words.length ? new RegExp(words.map(escapeRegex).join('|'), 'i') : null;
  const shopFilter = { 'verification.status': 'approved', isActive: true };
  const approved = await Business.find(shopFilter).select('_id name rating category').populate('category', 'name').limit(300);
  const ids = approved.map((b) => b._id);
  const shopName = new Map(approved.map((b) => [String(b._id), b.name]));

  const productQuery = { business: { $in: ids }, isActive: true };
  if (rx) productQuery.$or = [{ name: rx }, { tags: rx }, { description: rx }];
  let products = await Product.find(productQuery).sort('-rating.avg').limit(6).select('name price business rating stock images');
  if (!products.length && rx) products = await Product.find({ business: { $in: ids }, isActive: true }).sort('-rating.avg').limit(4).select('name price business rating stock images');

  // Shops worth mentioning: ones matching the words, the shops that sell the matched products, then the best rated.
  const byId = new Map(approved.map((b) => [String(b._id), b]));
  const picked = new Map();
  const add = (b) => { if (b && picked.size < 4) picked.set(String(b._id), b); };
  if (rx) approved.filter((b) => rx.test(b.name) || rx.test(b.category?.name || '')).forEach(add);
  products.forEach((p) => add(byId.get(String(p.business))));
  [...approved].sort((a, b) => (b.rating?.avg || 0) - (a.rating?.avg || 0)).forEach((b) => { if (picked.size < 3) add(b); });
  const shops = [...picked.values()];

  const catalogue = {
    products: products.map((p) => ({
      id: String(p._id), name: p.name, priceRs: p.price, shop: shopName.get(String(p.business)) || '',
      rating: p.rating?.count ? p.rating.avg : null, inStock: (p.stock || 0) > 0,
    })),
    shops: shops.map((b) => ({ id: String(b._id), name: b.name, category: b.category?.name || '', rating: b.rating?.count ? b.rating.avg : null })),
  };
  if (ORDER_WORDS.test(message)) {
    const orders = await Order.find({ customer: userId }).sort('-createdAt').limit(3).populate('business', 'name').select('orderNumber status amounts.total business createdAt');
    catalogue.myRecentOrders = orders.map((o) => ({ orderNumber: o.orderNumber, status: o.status, totalRs: o.amounts?.total, shop: o.business?.name || '' }));
  }
  return { catalogue, products, shops };
}

exports.reply = async (userId, { message, history }) => {
  const { catalogue, products, shops } = await buildContext(userId, message);
  const out = await ai.generateAssistantReply({ message, history, guide: GUIDE, catalogue });
  // Only items that were actually in the data can be recommended; anything else the model "invented" is dropped.
  const prodById = new Map(products.map((p) => [String(p._id), p]));
  const shopById = new Map(shops.map((b) => [String(b._id), b]));
  return {
    reply: out.reply,
    products: [...new Set(out.productIds)].filter((id) => prodById.has(id)).slice(0, 4).map((id) => {
      const p = prodById.get(id);
      return { id, name: p.name, price: p.price, image: p.images?.[0] || null, shop: catalogue.products.find((c) => c.id === id)?.shop || '' };
    }),
    businesses: [...new Set(out.businessIds)].filter((id) => shopById.has(id)).slice(0, 3).map((id) => {
      const b = shopById.get(id);
      return { id, name: b.name, rating: b.rating?.count ? b.rating.avg : null };
    }),
    provider: out.provider,
  };
};

exports._buildContext = buildContext;
exports.GUIDE = GUIDE;
