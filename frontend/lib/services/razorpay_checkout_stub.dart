import 'razorpay_checkout_types.dart';
export 'razorpay_checkout_types.dart';

Future<CheckoutResult> openRazorpayCheckout(Map<String, dynamic> options) async =>
    const CheckoutResult('unavailable',
        description: 'Online payment is available in the web app.');
