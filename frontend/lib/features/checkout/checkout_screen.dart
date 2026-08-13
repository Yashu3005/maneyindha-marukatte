import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/widgets.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _line1 = TextEditingController();
  final _city = TextEditingController(text: 'Bengaluru');
  final _pincode = TextEditingController();
  bool _selfPickup = false;
  bool _placing = false;
  bool _payOnline = false;

  Future<void> _placeOrder(Map<String, dynamic> cart) async {
    setState(() => _placing = true);
    try {
      final items = ((cart['items'] as List?) ?? []).map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        final product = Map<String, dynamic>.from(item['product'] as Map);
        return {'productId': product['_id'], 'quantity': item['quantity']};
      }).toList();

      final business = cart['business'];
      final businessId = business is Map ? business['_id'] : business;

      final orderRes = await ApiClient.dio.post('/orders', data: {
        'businessId': businessId,
        'items': items,
        'isSelfPickup': _selfPickup,
        if (!_selfPickup)
          'deliveryAddress': {
            'line1': _line1.text.trim(),
            'city': _city.text.trim(),
            'pincode': _pincode.text.trim(),
          },
        if (cart['coupon'] != null) 'couponCode': cart['coupon'],
      });
      final orderId = (orderRes.data['data'] as Map)['_id'].toString();

      ref.invalidate(cartProvider);
      ref.invalidate(ordersProvider);

      if (_payOnline) {
        final linkRes = await ApiClient.dio
            .post('/payments/link', data: {'orderId': orderId});
        final url = (linkRes.data['data'] as Map)['url'].toString();
        await launchUrl(Uri.parse(url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Complete the payment, then tap "Verify payment" on your order.')));
          context.go('/orders');
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order placed 🎉 Pay on delivery.')));
        context.go('/orders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: cart.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e)),
        data: (c) {
          final items = (c['items'] as List?) ?? [];
          final totals = (c['totals'] as Map?) ?? {};
          if (items.isEmpty) {
            return const EmptyView(message: 'Nothing to check out.');
          }
          final canPlace = _selfPickup ||
              (_line1.text.isNotEmpty && _pincode.text.isNotEmpty);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Delivery', style: Theme.of(context).textTheme.titleLarge),
                  SwitchListTile(
                    title: const Text('Self pickup (no delivery fee)'),
                    value: _selfPickup,
                    onChanged: (v) => setState(() => _selfPickup = v),
                  ),
                  if (!_selfPickup) ...[
                    TextField(controller: _line1,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Address line')),
                    const SizedBox(height: 12),
                    TextField(controller: _city,
                        decoration: const InputDecoration(labelText: 'City')),
                    const SizedBox(height: 12),
                    TextField(controller: _pincode,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Pincode')),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Items total'),
                          Text(rupees(totals['subtotal'])),
                        ]),
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Delivery fee'),
                          Text(_selfPickup ? 'Free' : '₹30'),
                        ]),
                        if ((totals['discount'] ?? 0) != 0) ...[
                          const SizedBox(height: 4),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Discount'),
                            Text('- ${rupees(totals['discount'])}'),
                          ]),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Payment', style: Theme.of(context).textTheme.titleLarge),
                  RadioListTile<bool>(
                    title: const Text('Cash on delivery'),
                    value: false,
                    groupValue: _payOnline,
                    onChanged: (v) => setState(() => _payOnline = v ?? false),
                  ),
                  RadioListTile<bool>(
                    title: const Text('Pay online (UPI / cards / wallets)'),
                    subtitle: const Text('Opens a secure Razorpay page'),
                    value: true,
                    groupValue: _payOnline,
                    onChanged: (v) => setState(() => _payOnline = v ?? false),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (canPlace && !_placing) ? () => _placeOrder(c) : null,
                    child: Text(_placing ? 'Placing order…' : 'Place order'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
