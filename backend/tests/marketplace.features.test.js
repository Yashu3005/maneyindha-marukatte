process.env.JWT_SECRET = 'test-jwt-secret-marketplace';
process.env.JWT_REFRESH_SECRET = 'test-jwt-refresh-secret-marketplace';
process.env.NODE_ENV = 'test';

const mongoose = require('mongoose');
const reviewService = require('../src/services/review.service');
const emailService = require('../src/services/email.service');
const productController = require('../src/controllers/product.controller');
const Order = require('../src/models/Order');
const Product = require('../src/models/Product');
const Business = require('../src/models/Business');
const Review = require('../src/models/Review');

describe('Marketplace Features Tests', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('Verified Purchase Review System', () => {
    const dummyProduct = {
      _id: '64b1f2e1a5e1234567890123',
      name: 'Mysore Pak',
      business: '64b1f2e1a5e1234567890999',
      isActive: true,
    };

    test('rejects review when specified orderId is not delivered', async () => {
      jest.spyOn(Product, 'findOne').mockResolvedValue(dummyProduct);
      jest.spyOn(Order, 'findOne').mockResolvedValue(null); // not found or not delivered

      await expect(
        reviewService.createReview('user-customer-1', {
          productId: dummyProduct._id,
          orderId: '64b1f2e1a5e1234567890555',
          rating: 5,
          comment: 'Delicious!',
        })
      ).rejects.toThrow('No delivered order found for this product');
    });

    test('rejects review when customer has never purchased the product and orderId is omitted', async () => {
      jest.spyOn(Product, 'findOne').mockResolvedValue(dummyProduct);
      jest.spyOn(Order, 'findOne').mockReturnValue({
        sort: jest.fn().mockResolvedValue(null),
      });

      await expect(
        reviewService.createReview('user-customer-1', {
          productId: dummyProduct._id,
          rating: 4,
          comment: 'Looks great!',
        })
      ).rejects.toThrow('Verified purchase required: You can only review products from delivered orders');
    });

    test('creates verified review when customer has a delivered order', async () => {
      const deliveredOrder = {
        _id: '64b1f2e1a5e1234567890777',
        customer: 'user-customer-1',
        status: 'delivered',
      };
      jest.spyOn(Product, 'findOne').mockResolvedValue(dummyProduct);
      jest.spyOn(Order, 'findOne').mockReturnValue({
        sort: jest.fn().mockResolvedValue(deliveredOrder),
      });
      jest.spyOn(Review, 'create').mockResolvedValue({
        _id: 'rev-1',
        customer: 'user-customer-1',
        product: dummyProduct._id,
        order: deliveredOrder._id,
        rating: 5,
        isVerifiedPurchase: true,
      });
      jest.spyOn(Review, 'aggregate').mockResolvedValue([{ avg: 4.8, count: 5 }]);
      jest.spyOn(Product, 'findByIdAndUpdate').mockResolvedValue({});
      jest.spyOn(Business, 'findByIdAndUpdate').mockResolvedValue({});

      const result = await reviewService.createReview('user-customer-1', {
        productId: dummyProduct._id,
        rating: 5,
        comment: 'Authentic taste!',
      });

      expect(result.isVerifiedPurchase).toBe(true);
      expect(result.order).toBe(deliveredOrder._id);
    });
  });

  describe('Product Controller: Update Endpoint', () => {
    test('rejects update if product is not owned by the requesting entrepreneur', async () => {
      const existingProduct = {
        _id: 'prod-123',
        business: 'biz-1',
        isActive: true,
      };
      jest.spyOn(Product, 'findById').mockResolvedValue(existingProduct);
      jest.spyOn(Business, 'findOne').mockResolvedValue(null); // not owned

      const req = {
        params: { id: 'prod-123' },
        user: { id: 'intruder-seller' },
        body: { price: 250 },
      };
      const res = {};
      const next = jest.fn();

      await productController.update(req, res, next);

      expect(next).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'You can only edit products belonging to your shop' })
      );
    });

    test('updates product fields successfully when entrepreneur is authorized', async () => {
      const saveMock = jest.fn().mockResolvedValue(true);
      const existingProduct = {
        _id: 'prod-123',
        business: 'biz-1',
        isActive: true,
        name: 'Old Name',
        price: 200,
        stock: 5,
        save: saveMock,
      };
      jest.spyOn(Product, 'findById').mockResolvedValue(existingProduct);
      jest.spyOn(Business, 'findOne').mockResolvedValue({ _id: 'biz-1', owner: 'owner-seller' });

      let capturedStatus, capturedJson;
      const res = {
        status: (s) => { capturedStatus = s; return res; },
        json: (j) => { capturedJson = j; return res; },
      };
      const req = {
        params: { id: 'prod-123' },
        user: { id: 'owner-seller' },
        body: { name: 'Updated Homemade Nipattu', price: 240, stock: 25 },
      };
      const next = jest.fn();

      await productController.update(req, res, next);

      expect(next).not.toHaveBeenCalled();
      expect(existingProduct.name).toBe('Updated Homemade Nipattu');
      expect(existingProduct.price).toBe(240);
      expect(existingProduct.stock).toBe(25);
      expect(saveMock).toHaveBeenCalled();
      expect(capturedJson.data.name).toBe('Updated Homemade Nipattu');
    });

    test('rejects negative price or stock with 422', async () => {
      const existingProduct = {
        _id: 'prod-123',
        business: 'biz-1',
        isActive: true,
      };
      jest.spyOn(Product, 'findById').mockResolvedValue(existingProduct);
      jest.spyOn(Business, 'findOne').mockResolvedValue({ _id: 'biz-1', owner: 'owner-seller' });

      const req = {
        params: { id: 'prod-123' },
        user: { id: 'owner-seller' },
        body: { price: -50 },
      };
      const res = {};
      const next = jest.fn();

      await productController.update(req, res, next);

      expect(next).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Price must be a valid positive number' })
      );
    });
  });

  describe('Order Notification Email Generators', () => {
    test('generates branded order placed email HTML with accurate pricing', () => {
      const html = emailService.buildOrderPlacedHtml({
        orderNumber: 'MM12345678',
        customerName: 'Radha',
        items: [
          { name: 'Ragi Ladoo', quantity: 2, unitPrice: 120 },
          { name: 'Filter Coffee Powder', quantity: 1, unitPrice: 200 },
        ],
        amounts: { subtotal: 440, deliveryFee: 30, discount: 40, total: 430 },
        deliveryAddress: { line1: '12th Cross, Malleshwaram', city: 'Bengaluru', pincode: '560003' },
      });

      expect(html).toContain('MANEYINDHA MARUKATTE');
      expect(html).toContain('MM12345678');
      expect(html).toContain('Radha');
      expect(html).toContain('Ragi Ladoo');
      expect(html).toContain('Filter Coffee Powder');
      expect(html).toContain('₹430.00');
      expect(html).toContain('Malleshwaram');
    });

    test('generates branded order status update email HTML', () => {
      const html = emailService.buildOrderStatusHtml({
        orderNumber: 'MM12345678',
        customerName: 'Radha',
        newStatus: 'out_for_delivery',
        trackingNotes: 'Partner on electric scooter',
      });

      expect(html).toContain('MANEYINDHA MARUKATTE');
      expect(html).toContain('MM12345678');
      expect(html).toContain('Out for delivery to your address');
      expect(html).toContain('Partner on electric scooter');
    });

    test('generates branded seller order alert email HTML', () => {
      const html = emailService.buildSellerAlertHtml({
        sellerName: 'Savitha',
        orderNumber: 'MM12345678',
        items: [{ name: 'Handmade Kasuti Embroidery Pouch', quantity: 1 }],
        amounts: { total: 350 },
      });

      expect(html).toContain('Savitha');
      expect(html).toContain('MM12345678');
      expect(html).toContain('Handmade Kasuti Embroidery Pouch');
      expect(html).toContain('₹350.00');
    });

    test('returns unconfigured gracefully without crashing if RESEND_API_KEY is not set', async () => {
      const originalKey = process.env.RESEND_API_KEY;
      delete process.env.RESEND_API_KEY;

      const res = await emailService.sendOrderConfirmationEmail({
        to: 'customer@test.com',
        customerName: 'Customer',
        orderNumber: 'MM999',
        items: [],
        amounts: { total: 100 },
      });

      expect(res.delivered).toBe(false);
      expect(res.reason).toBe('unconfigured');

      process.env.RESEND_API_KEY = originalKey;
    });
  });
});
