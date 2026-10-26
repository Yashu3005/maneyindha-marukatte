process.env.JWT_SECRET = 'test-jwt-secret-payment';
process.env.JWT_REFRESH_SECRET = 'test-jwt-refresh-secret-payment';
process.env.RAZORPAY_KEY_ID = 'rzp_test_mock_key_12345';
process.env.RAZORPAY_KEY_SECRET = 'rzp_test_mock_secret_abcdef';
process.env.RAZORPAY_WEBHOOK_SECRET = 'rzp_test_webhook_secret_xyz';
process.env.NODE_ENV = 'test';

const crypto = require('crypto');
const paymentService = require('../src/services/payment.service');
const Order = require('../src/models/Order');
const Product = require('../src/models/Product');
const Transaction = require('../src/models/Transaction');

describe('Razorpay Payment Service (Test Mode)', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('createPaymentOrder', () => {
    test('rejects missing orderId with 422', async () => {
      await expect(paymentService.createPaymentOrder('user-1', {}))
        .rejects.toThrow('orderId is required');
    });

    test('enforces ownership check: cannot create payment for another user order', async () => {
      jest.spyOn(Order, 'findOne').mockResolvedValue(null);

      await expect(paymentService.createPaymentOrder('user-1', { orderId: 'foreign-order' }))
        .rejects.toThrow('Order not found or does not belong to you');
    });

    test('rejects payment initialization if order is not in pending state', async () => {
      const order = {
        _id: 'order-1',
        customer: 'user-1',
        status: 'delivered',
        amounts: { total: 350 },
      };
      jest.spyOn(Order, 'findOne').mockResolvedValue(order);

      await expect(paymentService.createPaymentOrder('user-1', { orderId: 'order-1' }))
        .rejects.toThrow("Cannot initiate payment for order in 'delivered' state");
    });

    test('creates payment order with trusted server-side total and pending Transaction', async () => {
      const saveSpy = jest.fn();
      const order = {
        _id: 'order-123',
        customer: 'user-1',
        orderNumber: 'MM1001',
        status: 'pending',
        amounts: { total: 420 },
        payment: {},
        save: saveSpy,
      };
      jest.spyOn(Order, 'findOne').mockResolvedValue(order);
      const txSpy = jest.spyOn(Transaction, 'findOneAndUpdate').mockResolvedValue({});
      jest.spyOn(paymentService, 'getRazorpayClient').mockReturnValue({
        orders: {
          create: jest.fn().mockResolvedValue({ id: 'order_mock_12345' }),
        },
      });

      const result = await paymentService.createPaymentOrder('user-1', { orderId: 'order-123' });

      expect(result.amount).toBe(420);
      expect(result.amountInPaise).toBe(42000);
      expect(result.currency).toBe('INR');
      expect(result.razorpayOrderId).toBe('order_mock_12345');
      expect(result.keyId).toBe('rzp_test_mock_key_12345');
      expect(saveSpy).toHaveBeenCalledTimes(1);
      expect(txSpy).toHaveBeenCalledTimes(1);
    });
  });

  describe('verifyPayment (Signature Verification & Security)', () => {
    test('fails verification and restores inventory when signature does not match', async () => {
      const saveSpy = jest.fn();
      const order = {
        _id: 'order-123',
        customer: 'user-1',
        orderNumber: 'MM1001',
        status: 'pending',
        statusHistory: [],
        items: [{ product: 'prod-1', quantity: 2 }],
        payment: { status: 'pending' },
        save: saveSpy,
      };
      jest.spyOn(Order, 'findOne').mockResolvedValue(order);
      jest.spyOn(Transaction, 'findOneAndUpdate').mockResolvedValue({});
      const productUpdateSpy = jest.spyOn(Product, 'updateOne').mockResolvedValue({});

      const rzpOrderId = 'order_xyz123';
      const rzpPaymentId = 'pay_abc999';
      const invalidSignature = 'invalid_forged_signature_hash_00000000000000000000000000000000';

      await expect(
        paymentService.verifyPayment('user-1', {
          orderId: 'order-123',
          razorpayOrderId: rzpOrderId,
          razorpayPaymentId: rzpPaymentId,
          razorpaySignature: invalidSignature,
        })
      ).rejects.toThrow('Payment signature verification failed');

      expect(order.status).toBe('payment_failed');
      expect(order.payment.status).toBe('failed');
      expect(productUpdateSpy).toHaveBeenCalledWith(
        { _id: 'prod-1' },
        { $inc: { stock: 2 } }
      );
    });

    test('successfully confirms order and marks transaction success on valid signature', async () => {
      const saveSpy = jest.fn();
      const order = {
        _id: 'order-123',
        customer: 'user-1',
        orderNumber: 'MM1001',
        status: 'pending',
        statusHistory: [],
        items: [{ product: 'prod-1', quantity: 1 }],
        payment: { status: 'pending' },
        save: saveSpy,
      };
      jest.spyOn(Order, 'findOne').mockResolvedValue(order);
      const txSpy = jest.spyOn(Transaction, 'findOneAndUpdate').mockResolvedValue({});

      const rzpOrderId = 'order_valid_123';
      const rzpPaymentId = 'pay_valid_456';
      // Compute correct HMAC-SHA256 signature
      const validSignature = crypto
        .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
        .update(`${rzpOrderId}|${rzpPaymentId}`)
        .digest('hex');

      const result = await paymentService.verifyPayment('user-1', {
        orderId: 'order-123',
        razorpayOrderId: rzpOrderId,
        razorpayPaymentId: rzpPaymentId,
        razorpaySignature: validSignature,
      });

      expect(result.verified).toBe(true);
      expect(order.status).toBe('confirmed');
      expect(order.payment.status).toBe('paid');
      expect(order.payment.razorpayPaymentId).toBe(rzpPaymentId);
      expect(saveSpy).toHaveBeenCalledTimes(1);
      expect(txSpy).toHaveBeenCalledWith(
        { order: 'order-123', type: 'payment' },
        expect.objectContaining({ status: 'success' })
      );
    });

    test('is idempotent: returns already processed state without duplicate transitions', async () => {
      const order = {
        _id: 'order-already-paid',
        customer: 'user-1',
        status: 'confirmed',
        payment: { status: 'paid' },
      };
      jest.spyOn(Order, 'findOne').mockResolvedValue(order);

      const result = await paymentService.verifyPayment('user-1', {
        orderId: 'order-already-paid',
        razorpayOrderId: 'ord_1',
        razorpayPaymentId: 'pay_1',
      });

      expect(result.verified).toBe(true);
      expect(result.alreadyProcessed).toBe(true);
    });
  });

  describe('handleWebhook (Server-to-Server Callbacks)', () => {
    test('rejects webhook with invalid signature', async () => {
      const rawBody = JSON.stringify({ event: 'payment.captured' });
      await expect(
        paymentService.handleWebhook(rawBody, 'invalid-sig', { event: 'payment.captured' })
      ).rejects.toThrow('Invalid webhook signature');
    });

    test('processes payment.captured event and updates order status to paid', async () => {
      const eventPayload = {
        event: 'payment.captured',
        payload: {
          payment: {
            entity: {
              id: 'pay_webhook_999',
              order_id: 'order_webhook_123',
            },
          },
        },
      };
      const rawBody = JSON.stringify(eventPayload);
      const validWebhookSig = crypto
        .createHmac('sha256', process.env.RAZORPAY_WEBHOOK_SECRET)
        .update(rawBody)
        .digest('hex');

      const saveSpy = jest.fn();
      const order = {
        _id: 'ord-wh-1',
        status: 'pending',
        statusHistory: [],
        payment: { status: 'pending' },
        save: saveSpy,
      };
      jest.spyOn(Order, 'findOne').mockResolvedValue(order);
      jest.spyOn(Transaction, 'findOneAndUpdate').mockResolvedValue({});

      const res = await paymentService.handleWebhook(rawBody, validWebhookSig, eventPayload);
      expect(res.status).toBe('processed');
      expect(order.status).toBe('confirmed');
      expect(order.payment.status).toBe('paid');
      expect(saveSpy).toHaveBeenCalledTimes(1);
    });

    test('processes payment.failed webhook event and restores inventory', async () => {
      const eventPayload = {
        event: 'payment.failed',
        payload: {
          payment: {
            entity: {
              id: 'pay_fail_000',
              order_id: 'order_fail_123',
              error_description: 'Card declined by issuing bank',
            },
          },
        },
      };
      const rawBody = JSON.stringify(eventPayload);
      const validWebhookSig = crypto
        .createHmac('sha256', process.env.RAZORPAY_WEBHOOK_SECRET)
        .update(rawBody)
        .digest('hex');

      const saveSpy = jest.fn();
      const order = {
        _id: 'ord-fail-1',
        status: 'pending',
        statusHistory: [],
        items: [{ product: 'prod-item-1', quantity: 3 }],
        payment: { status: 'pending' },
        save: saveSpy,
      };
      jest.spyOn(Order, 'findOne').mockResolvedValue(order);
      jest.spyOn(Transaction, 'findOneAndUpdate').mockResolvedValue({});
      const stockRestoreSpy = jest.spyOn(Product, 'updateOne').mockResolvedValue({});

      const res = await paymentService.handleWebhook(rawBody, validWebhookSig, eventPayload);
      expect(res.status).toBe('processed');
      expect(order.status).toBe('payment_failed');
      expect(order.payment.status).toBe('failed');
      expect(stockRestoreSpy).toHaveBeenCalledWith(
        { _id: 'prod-item-1' },
        { $inc: { stock: 3 } }
      );
    });
  });
});
