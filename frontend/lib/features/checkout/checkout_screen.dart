import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import 'pay_flow.dart';

const _deliveryFee = 30; // mirrors the server's flat fee; the server's number is the one charged

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
  String _payment = 'cod'; // cod | razorpay

  num _num(dynamic v) => v is num ? v : (num.tryParse('${v ?? 0}') ?? 0);

  num _payable(Map totals) {
    final base = _num(totals['total'] ?? totals['subtotal']);
    return base + (_selfPickup ? 0 : _deliveryFee);
  }

  /// "Confirm your order" pop-up. Returns true when the customer taps Confirm.
  Future<bool> _confirm(Map<String, dynamic> cart) async {
    final items = (cart['items'] as List?) ?? [];
    final totals = (cart['totals'] as Map?) ?? {};
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Text('Confirm your order', style: serif(22))),
              const SizedBox(height: 14),
              ...items.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                final product = Map<String, dynamic>.from(item['product'] as Map);
                final q = _num(item['quantity']);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Text('$q ×', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(product['name']?.toString() ?? '', overflow: TextOverflow.ellipsis)),
                    Text(rupees(_num(product['price']) * q)),
                  ]),
                );
              }),
              const Divider(height: 24),
              _confirmLine(Icons.delivery_dining_outlined, _selfPickup ? 'Self pickup' : 'Deliver to',
                  _selfPickup ? 'You will collect it from the shop' : '${_line1.text.trim()}, ${_city.text.trim()} ${_pincode.text.trim()}'),
              const SizedBox(height: 8),
              _confirmLine(
                  _payment == 'cod' ? Icons.payments_outlined : Icons.lock_outline,
                  'Payment',
                  _payment == 'cod' ? 'Cash on delivery' : 'Pay online (Razorpay)'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: MMColors.blush, borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  _sumRow('Items', rupees(totals['subtotal'])),
                  if (_num(totals['discount']) != 0) _sumRow('Discount', '- ${rupees(totals['discount'])}'),
                  _sumRow('Delivery', _selfPickup ? 'Free' : rupees(_deliveryFee)),
                  const Divider(),
                  _sumRow('You pay', rupees(_payable(totals)), bold: true),
                ]),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Edit'))),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.check),
                    label: Text(_payment == 'razorpay' ? 'Confirm & pay' : 'Confirm order'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    return res == true;
  }

  Widget _confirmLine(IconData icon, String title, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: MMColors.moss),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 12)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      );

  Widget _sumRow(String l, String v, {bool bold = false}) {
    final st = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: st), Text(v, style: st)]),
    );
  }

  Future<void> _onPlacePressed(Map<String, dynamic> cart) async {
    if (!await _confirm(cart) || !mounted) return;
    await _placeOrder(cart);
  }

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

      final created = await ApiClient.dio.post('/orders', data: {
        'businessId': businessId,
        'items': items,
        'isSelfPickup': _selfPickup,
        'paymentMethod': _payment,
        if (!_selfPickup)
          'deliveryAddress': {
            'line1': _line1.text.trim(),
            'city': _city.text.trim(),
            'pincode': _pincode.text.trim(),
          },
        if (cart['coupon'] != null) 'couponCode': cart['coupon'],
      });

      ref.invalidate(cartProvider);
      ref.invalidate(ordersProvider);
      final data = Map<String, dynamic>.from(created.data['data'] as Map);
      final orderNumber = data['orderNumber']?.toString();

      var paid = true; // true = nothing more is owed right now
      var message = 'Pay on delivery.';
      if (_payment == 'razorpay') {
        final outcome = await payForOrder(data['_id'].toString());
        paid = outcome.paid;
        message = outcome.message;
        ref.invalidate(ordersProvider);
      }
      if (!mounted) return;
      if (paid) {
        await showSuccessDialog(
          context,
          title: 'Order placed!',
          message: '${orderNumber != null ? 'Order $orderNumber\n' : ''}$message\nThe shop has been notified.',
          primaryLabel: 'Track my order',
          onPrimary: () { if (mounted) context.go('/orders'); },
          secondaryLabel: 'Continue shopping',
          onSecondary: () { if (mounted) context.go('/app'); },
        );
      } else {
        // The order exists but payment is not confirmed: say so plainly, never "success".
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        context.go('/orders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Widget _payTile(String value, IconData icon, String title, String subtitle) {
    final selected = _payment == value;
    return GestureDetector(
      onTap: () => setState(() => _payment = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? MMColors.sage.withOpacity(0.6) : MMColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? MMColors.deepOlive : MMColors.sage, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: MMColors.deepOlive),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? MMColors.deepOlive : Colors.black38),
        ]),
      ),
    );
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
              (_line1.text.trim().isNotEmpty && _pincode.text.trim().isNotEmpty);
          return Column(children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SectionHeader(icon: Icons.local_shipping_outlined, title: 'Delivery',
                          subtitle: 'Where should we bring it?'),
                      SoftCard(
                        child: Column(children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Self pickup'),
                            subtitle: const Text('Collect from the shop, no delivery fee'),
                            value: _selfPickup,
                            onChanged: (v) => setState(() => _selfPickup = v),
                          ),
                          if (!_selfPickup) ...[
                            const SizedBox(height: 4),
                            TextField(controller: _line1,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                    labelText: 'Address line', prefixIcon: Icon(Icons.home_outlined))),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: TextField(controller: _city,
                                    decoration: const InputDecoration(labelText: 'City')),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(controller: _pincode,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(labelText: 'Pincode')),
                              ),
                            ]),
                          ],
                        ]),
                      ),
                      const SectionHeader(icon: Icons.payments_outlined, title: 'Payment'),
                      _payTile('cod', Icons.money, 'Cash on delivery', 'Pay when your order arrives'),
                      _payTile('razorpay', Icons.lock_outline, 'Pay online',
                          'UPI, card or netbanking · secure checkout by Razorpay'),
                      const SectionHeader(icon: Icons.receipt_long_outlined, title: 'Summary'),
                      SoftCard(
                        child: Column(children: [
                          _sumRow('Items total', rupees(totals['subtotal'])),
                          _sumRow('Delivery fee', _selfPickup ? 'Free' : rupees(_deliveryFee)),
                          if (_num(totals['discount']) != 0)
                            _sumRow('Discount', '- ${rupees(totals['discount'])}'),
                          const Divider(),
                          _sumRow('You pay', rupees(_payable(totals)), bold: true),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: MMColors.card,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (canPlace && !_placing) ? () => _onPlacePressed(Map<String, dynamic>.from(c)) : null,
                          icon: _placing
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: MMColors.cream))
                              : const Icon(Icons.shopping_bag_outlined),
                          label: Text(_placing
                              ? 'Please wait…'
                              : 'Review order · ${rupees(_payable(totals))}'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
