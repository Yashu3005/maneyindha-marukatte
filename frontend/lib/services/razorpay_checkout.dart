// Conditional export: real Checkout on web, an "unavailable" stub elsewhere.
export 'razorpay_checkout_stub.dart'
    if (dart.library.js_interop) 'razorpay_checkout_web.dart';
