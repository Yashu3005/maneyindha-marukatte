// Thin bridge between Flutter web and Razorpay Standard Checkout.
// Only the PUBLIC key id and server-created order id are used here; the key secret never reaches the browser.
// Resolves to a JSON string: {status:'success'|'dismissed'|'failed', ...}. The success payload is NOT trusted by the
// app — it is sent to the backend, which verifies the signature and confirms the payment with Razorpay.
(function () {
  var SRC = 'https://checkout.razorpay.com/v1/checkout.js';
  function load() {
    return new Promise(function (resolve, reject) {
      if (window.Razorpay) return resolve();
      var s = document.createElement('script');
      s.src = SRC; s.async = true;
      s.onload = function () { resolve(); };
      s.onerror = function () { reject(new Error('Could not load Razorpay Checkout')); };
      document.head.appendChild(s);
    });
  }
  window.mmOpenRazorpay = function (optionsJson) {
    var opts = JSON.parse(optionsJson);
    return load().then(function () {
      return new Promise(function (resolve) {
        var done = false;
        function finish(v) { if (!done) { done = true; resolve(JSON.stringify(v)); } }
        opts.handler = function (r) {
          finish({ status: 'success', razorpay_order_id: r.razorpay_order_id,
                   razorpay_payment_id: r.razorpay_payment_id, razorpay_signature: r.razorpay_signature });
        };
        opts.modal = { ondismiss: function () { finish({ status: 'dismissed' }); } };
        var rzp = new window.Razorpay(opts);
        rzp.on('payment.failed', function (resp) {
          finish({ status: 'failed', description: resp && resp.error && resp.error.description });
        });
        rzp.open();
      });
    }).catch(function (e) { return JSON.stringify({ status: 'unavailable', description: String(e && e.message) }); });
  };
})();
