const Product = require('../src/models/Product');
const Order = require('../src/models/Order');
const Business = require('../src/models/Business');
const SupportTicket = require('../src/models/SupportTicket');
const ActivityLog = require('../src/models/ActivityLog');

describe('Extended Schema & Business Rule Unit Tests', () => {
  describe('Product Schema & After-Sales Options', () => {
    test('Default delivery options and after-sales support schema structure', () => {
      const p = new Product({
        business: '507f191e810c19729de860ea',
        name: 'Handmade Scented Candle',
        price: 299,
        category: '507f191e810c19729de860eb',
      });
      expect(p.deliveryOptions.pickup).toBe(true);
      expect(p.deliveryOptions.freeDelivery).toBe(false);
      expect(p.deliveryOptions.deliveryCharge).toBe(30);
      expect(p.afterSales.supportType).toBe('not_available');
      expect(p.moderation.status).toBe('active');
    });

    test('Customization allowed configuration', () => {
      const p = new Product({
        business: '507f191e810c19729de860ea',
        name: 'Custom Embroidered Bag',
        price: 499,
        category: '507f191e810c19729de860eb',
        isCustomOrder: true,
        customizations: [
          {
            label: 'Enter custom initials or embroidery design',
            fieldType: 'text',
            required: true,
          },
        ],
      });
      expect(p.isCustomOrder).toBe(true);
      expect(p.customizations.length).toBe(1);
      expect(p.customizations[0].label).toBe('Enter custom initials or embroidery design');
    });
  });

  describe('Order State Machine & After-Sales Workflow', () => {
    test('Single entrepreneur enforcement in order structure', () => {
      const order = new Order({
        customer: '507f191e810c19729de860e1',
        business: '507f191e810c19729de860ea',
        items: [
          {
            product: '507f191e810c19729de860e2',
            name: 'Chocolate Cake',
            price: 549,
            quantity: 1,
            customization: 'Happy Birthday Yashu',
          },
        ],
        subtotal: 549,
        deliveryFee: 30,
        total: 579,
        deliveryAddress: {
          line1: '123 Main Rd',
          city: 'Bengaluru',
          state: 'KA',
          pincode: '560001',
        },
      });

      expect(order.business.toString()).toBe('507f191e810c19729de860ea');
      expect(order.afterSales.status).toBe('none');
      expect(order.status).toBe('pending');
    });

    test('After-sales return status validation', () => {
      const validStatuses = [
        'none',
        'requested',
        'approved',
        'rejected',
        'return_initiated',
        'return_received',
        'completed',
      ];
      validStatuses.forEach((status) => {
        const order = new Order({
          customer: '507f191e810c19729de860e1',
          business: '507f191e810c19729de860ea',
          items: [{ name: 'Test', price: 100, quantity: 1 }],
          subtotal: 100,
          deliveryFee: 0,
          total: 100,
          deliveryAddress: { line1: 'Test', city: 'BLR', state: 'KA', pincode: '560001' },
          afterSales: { status },
        });
        expect(order.afterSales.status).toBe(status);
      });
    });
  });

  describe('SupportTicket & ActivityLog Schemas', () => {
    test('Support ticket creation with categories and defaults', () => {
      const ticket = new SupportTicket({
        ticketNumber: 'TCK-2026-1001',
        customer: '507f191e810c19729de860e1',
        issueType: 'Refund Appeal',
        description: 'I handed over the item to the entrepreneur.',
      });
      expect(ticket.status).toBe('open');
      expect(ticket.issueType).toBe('Refund Appeal');
    });

    test('Admin ActivityLog schema audit logging', () => {
      const log = new ActivityLog({
        admin: '507f191e810c19729de860e9',
        action: 'VERIFY_ENTREPRENEUR',
        targetType: 'Business',
        targetId: '507f191e810c19729de860ea',
        details: { status: 'approved', notes: 'All docs verified' },
      });
      expect(log.action).toBe('VERIFY_ENTREPRENEUR');
      expect(log.targetType).toBe('Business');
    });
  });
});
