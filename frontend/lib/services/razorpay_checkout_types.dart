/// Outcome of the Razorpay Checkout modal. NOT proof of payment — the backend must verify it.
class CheckoutResult {
  final String status; // success | dismissed | failed | unavailable
  final String? orderId, paymentId, signature, description;
  const CheckoutResult(this.status,
      {this.orderId, this.paymentId, this.signature, this.description});
}
