# Payment Architecture (Razorpay)

## Lifecycle

```
Cart → POST /orders (status: pending, payment: pending)
     → POST /payments/initiate  → backend creates Razorpay order → returns order_id
     → client opens Razorpay checkout (UPI/GPay/PhonePe/Paytm/cards/wallet)
     → client posts {payment_id, order_id, signature} → POST /payments/verify
     → backend verifies HMAC signature with RAZORPAY_KEY_SECRET
     → webhook (payment.captured) confirms independently
     → order → confirmed, payment → paid
```

## Rules

1. **Never trust the client.** Order amount comes from server-side pricing
   (see `services/order.service.js`); signature verification + webhook are
   the only sources of payment truth.
2. **Idempotency**: webhook handlers must be idempotent (duplicate delivery).
3. **COD**: order confirmed immediately, payment marked paid on delivery OTP.
4. **Refunds**: via Razorpay refund API, order transitions to `refunded`,
   transaction record written.
5. **Money as integer paise** from Phase 8 onward.
6. Stripe-ready: payment logic behind a service interface, same pattern as AI layer.
