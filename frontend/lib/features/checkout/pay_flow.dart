import '../../services/api_client.dart';
import '../../services/razorpay_checkout.dart';

/// What the UI should say. The wording is driven by the BACKEND's payment status only.
class PayOutcome {
  final bool paid; // backend says paid
  final String message;
  const PayOutcome(this.paid, this.message);
}

Map<String, dynamic> _data(dynamic res) =>
    Map<String, dynamic>.from((res.data['data'] ?? {}) as Map);

/// Pays for one of the caller's own pending online-payment orders.
/// Amount and order are created on the server; the browser success callback is only forwarded to /verify.
Future<PayOutcome> payForOrder(String orderId) async {
  try {
    final p = _data(await ApiClient.dio
        .post('/payments/razorpay/order', data: {'orderId': orderId}));
    final result = await openRazorpayCheckout({
      'key': p['keyId'],
      'order_id': p['razorpayOrderId'],
      'amount': p['amount'],
      'currency': p['currency'],
      'name': 'Maneyindha Marukatte',
      'description': 'Order ${p['orderNumber']}',
      'prefill': {
        if (p['prefill']?['name'] != null) 'name': p['prefill']['name'],
        if (p['prefill']?['email'] != null) 'email': p['prefill']['email'],
        if (p['prefill']?['contact'] != null) 'contact': p['prefill']['contact'],
      },
    });
    switch (result.status) {
      case 'success':
        final v = _data(await ApiClient.dio.post('/payments/razorpay/verify', data: {
          'orderId': orderId,
          'razorpay_order_id': result.orderId,
          'razorpay_payment_id': result.paymentId,
          'razorpay_signature': result.signature,
        }));
        return switch (v['paymentStatus']) {
          'paid' => const PayOutcome(true, 'Payment confirmed. The shop has been notified.'),
          'failed' => const PayOutcome(false, 'Payment failed. You can try again from My orders.'),
          _ => const PayOutcome(false, 'Payment is being confirmed. Check My orders shortly.'),
        };
      case 'failed':
        return PayOutcome(false, result.description ?? 'Payment failed. You can try again from My orders.');
      case 'dismissed':
        return const PayOutcome(false, 'Payment not completed. You can pay from My orders.');
      default:
        return PayOutcome(false, result.description ?? 'Online payment is unavailable right now.');
    }
  } catch (e) {
    return PayOutcome(false, apiError(e));
  }
}
