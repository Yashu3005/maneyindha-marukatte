import 'dart:convert';
import 'dart:js_interop';
import 'razorpay_checkout_types.dart';
export 'razorpay_checkout_types.dart';

@JS('mmOpenRazorpay')
external JSPromise<JSString> _open(JSString optionsJson);

Future<CheckoutResult> openRazorpayCheckout(Map<String, dynamic> options) async {
  try {
    final raw = (await _open(jsonEncode(options).toJS).toDart).toDart;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return CheckoutResult(m['status'] as String? ?? 'failed',
        orderId: m['razorpay_order_id'] as String?,
        paymentId: m['razorpay_payment_id'] as String?,
        signature: m['razorpay_signature'] as String?,
        description: m['description'] as String?);
  } catch (_) {
    return const CheckoutResult('unavailable',
        description: 'Could not open the payment window.');
  }
}
