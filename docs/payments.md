# Payments (Razorpay Standard Checkout)

Online payment is **optional**; cash on delivery remains the default (`paymentMethod: "cod"`). **Use Razorpay Test-mode keys until you deliberately go live** — this repository's tests never contact Razorpay.

## Flow
```
POST /orders {paymentMethod:"razorpay", ...}         order created, status pending, payment.status pending
POST /payments/razorpay/order {orderId}              server creates the Razorpay order (amount from DB total × 100 paise)
   -> browser opens Razorpay Checkout with keyId + razorpayOrderId   (public key id only)
   -> on success the browser posts {orderId, razorpay_order_id, razorpay_payment_id, razorpay_signature}
POST /payments/razorpay/verify                       server checks signature, fetches the payment from Razorpay, checks status/amount/currency
POST /payments/razorpay/webhook   (Razorpay -> server) independent confirmation: payment.captured / order.paid / payment.failed
GET  /payments/status/:orderId                       what the UI shows
```

## Guarantees (each is covered by a test in `backend/tests/payment.test.js`)
1. **Server-side amount.** The Razorpay order amount is `round(order.amounts.total × 100)`; any `amount` in the request is ignored.
2. **Signature verification.** `HMAC-SHA256(secret = RAZORPAY_KEY_SECRET, message = "<razorpay_order_id>|<razorpay_payment_id>")`, using the Razorpay order id **stored on our server**, compared in constant time. Bad, missing or malformed signatures → 400, nothing changes.
3. **Not trusting the callback.** After a valid signature the server still fetches the payment from Razorpay and requires `status = captured`, the same order id, the same amount and `INR`. `authorized` stays pending; `failed` is recorded; if Razorpay cannot be reached the order stays pending and the webhook finalises it.
4. **Webhook on the raw body.** `X-Razorpay-Signature` is verified over the exact bytes received (the route is mounted before `express.json`). Wrong signature → 400.
5. **Idempotency.** Events are de-duplicated on `X-Razorpay-Event-Id` (unique index, 90-day TTL). Paying is a compare-and-set on `payment.status`, so a second event for the same payment (or `order.paid` after `payment.captured`) writes no second ledger entry and fulfils nothing twice. A failed processing attempt releases the event id so Razorpay's retry is processed.
6. **Ownership.** Only the customer who placed the order can create/verify/query its payment; others get `404`.
7. **Fulfilment gate.** A shop cannot move an online-payment order to `confirmed` until `payment.status = paid` (`409 PAYMENT_PENDING`).
8. **Persisted state.** `orders.payment.{method,status,razorpayOrderId,razorpayPaymentId,amountPaise,paidAt,failureReason,needsRefund}`; a successful payment also writes a `transactions` row.
9. **UI = backend truth.** The Flutter app shows the outcome returned by `/verify` / `/status`, never the Checkout callback itself.

## Not implemented (be aware)
- **Refunds.** Cancelling or rejecting an *already paid* online order sets `payment.needsRefund = true` and logs a warning; the refund itself must be issued from the Razorpay dashboard. No refund API call is made.
- Payment is online-only on **web** (Checkout.js). On other platforms the app reports that online payment is unavailable and COD still works.
- COD orders are not marked "paid" automatically on delivery.
- Webhook ordering: events may arrive before the browser callback; both paths are safe.

## Setup (Test mode)
1. In the Razorpay dashboard (Test mode) create API keys → `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`.
2. Create a webhook pointing at `https://<your-api>/api/v1/payments/razorpay/webhook`, subscribe to `payment.captured`, `payment.failed`, `order.paid`, and put the secret you chose into `RAZORPAY_WEBHOOK_SECRET`. For local testing expose your API with a tunnel of your choice.
3. Pay with Razorpay's documented **test** cards/UPI ids ([Razorpay docs](https://razorpay.com/docs/)). No real money moves in Test mode.
4. Going live is a separate, deliberate step: swap in Live keys, re-register the webhook, and re-test. This repository has not been exercised against Razorpay at all (see `IMPLEMENTATION_REPORT.md`).

Money in orders is stored as rupees (`Number`); Razorpay amounts are integer paise.
