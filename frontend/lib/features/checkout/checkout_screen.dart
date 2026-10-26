// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _line1 = TextEditingController();
  final _city = TextEditingController(text: 'Bengaluru');
  final _pincode = TextEditingController();
  final _notes = TextEditingController();
  bool _selfPickup = false;
  String _paymentMethod = 'cod';
  bool _placing = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final user = ref.read(authProvider).user;
      final addresses = (user?['addresses'] as List?) ?? [];
      if (addresses.isNotEmpty) {
        final addr = addresses.first as Map;
        _line1.text = addr['line1']?.toString() ?? '';
        if (addr['city'] != null && addr['city'].toString().isNotEmpty) {
          _city.text = addr['city'].toString();
        }
        _pincode.text = addr['pincode']?.toString() ?? '560001';
      }
      _initialized = true;
    }
  }

  Future<void> _placeOrder(Map<String, dynamic> cart) async {
    final canPlace = _selfPickup ||
        (_line1.text.trim().isNotEmpty && _pincode.text.trim().isNotEmpty);

    if (!canPlace) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your delivery address and pincode')),
      );
      return;
    }

    setState(() => _placing = true);
    try {
      final items = ((cart['items'] as List?) ?? []).map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        final product = Map<String, dynamic>.from(item['product'] as Map);
        return {'productId': product['_id'], 'quantity': item['quantity']};
      }).toList();

      final business = cart['business'];
      final businessId = business is Map ? business['_id'] : business;

      final res = await ApiClient.dio.post('/orders', data: {
        'businessId': businessId,
        'items': items,
        'isSelfPickup': _selfPickup,
        if (!_selfPickup)
          'deliveryAddress': {
            'line1': _line1.text.trim(),
            'city': _city.text.trim(),
            'pincode': _pincode.text.trim(),
          },
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        if (cart['coupon'] != null) 'couponCode': cart['coupon'],
      });

      final orderData = res.data['data'] as Map<String, dynamic>;
      final orderNumber = orderData['orderNumber'] ?? 'MM';

      ref.invalidate(cartProvider);
      ref.invalidate(ordersProvider);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      color: MMColors.sageLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      size: 48,
                      color: MMColors.deepOlive,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Order Placed Successfully! 🎉',
                      textAlign: TextAlign.center,
                      style: serif(20, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Order #$orderNumber',
                      style: sans(14, weight: FontWeight.w700, color: MMColors.deepOlive)),
                  const SizedBox(height: 12),
                  Text(
                    'The home kitchen has received your request and will start preparing fresh. Pay upon delivery.',
                    textAlign: TextAlign.center,
                    style: sans(14, color: MMColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go('/orders');
                },
                child: const Text('View in My Orders'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e))),
        );
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
        loading: () => const LoadingView(message: 'Preparing checkout…'),
        error: (e, _) => ErrorView(message: apiError(e)),
        data: (c) {
          final items = (c['items'] as List?) ?? [];
          final totals = (c['totals'] as Map?) ?? {};
          final subtotal = (totals['subtotal'] ?? 0) as num;
          final discount = (totals['discount'] ?? 0) as num;
          final deliveryFee = _selfPickup ? 0 : 30;
          final totalAmount = subtotal - discount + deliveryFee;

          if (items.isEmpty) {
            return const EmptyView(message: 'Nothing to check out.');
          }

          return ResponsiveContainer(
            maxWidth: 720,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ListView(
              children: [
                // Delivery Option Switch
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fulfillment Preference', style: serif(18, weight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _fulfillmentOption(
                                title: 'Doorstep Delivery',
                                subtitle: 'Freshly delivered (₹30)',
                                icon: Icons.delivery_dining_rounded,
                                selected: !_selfPickup,
                                onTap: () => setState(() => _selfPickup = false),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _fulfillmentOption(
                                title: 'Self Pickup',
                                subtitle: 'Pickup from kitchen (Free)',
                                icon: Icons.storefront_rounded,
                                selected: _selfPickup,
                                onTap: () => setState(() => _selfPickup = true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Delivery Address Form
                if (!_selfPickup) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Delivery Address', style: serif(18, weight: FontWeight.w700)),
                              const Icon(Icons.location_on_outlined, size: 20, color: MMColors.terracotta),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _line1,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Street Address, Flat / House No.',
                              hintText: 'e.g. 104, Green Meadows, Indiranagar',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _city,
                                  decoration: const InputDecoration(labelText: 'City'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _pincode,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(labelText: 'Pincode'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notes,
                            decoration: const InputDecoration(
                              labelText: 'Special Cooking / Delivery Instructions (Optional)',
                              hintText: 'e.g. Less spicy, call before ringing bell',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Payment Mode Selection
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payment Method', style: serif(18, weight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        RadioListTile<String>(
                          value: 'cod',
                          groupValue: _paymentMethod,
                          onChanged: (v) => setState(() => _paymentMethod = v ?? 'cod'),
                          title: const Text('Cash on Delivery (UPI / Cash upon arrival)'),
                          subtitle: const Text('Pay the entrepreneur or courier when your order arrives'),
                          secondary: const Icon(Icons.handshake_outlined, color: MMColors.deepOlive),
                          activeColor: MMColors.deepOlive,
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>(
                          value: 'razorpay',
                          groupValue: _paymentMethod,
                          onChanged: null, // Disabled until Phase 4 live activation
                          title: Row(
                            children: [
                              const Text('Razorpay (Online UPI / Cards)'),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: MMColors.sageLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Phase 4',
                                    style: sans(10,
                                        weight: FontWeight.w700,
                                        color: MMColors.deepOlive)),
                              ),
                            ],
                          ),
                          subtitle: const Text('Instant UPI, Google Pay, Cards (Test mode in Phase 4)'),
                          secondary: const Icon(Icons.payment_rounded, color: MMColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Bill Summary Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order Summary', style: serif(18, weight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        _summaryRow('Items Total', rupees(subtotal)),
                        const SizedBox(height: 8),
                        _summaryRow('Delivery Charges', _selfPickup ? 'FREE' : '₹30'),
                        if (discount > 0) ...[
                          const SizedBox(height: 8),
                          _summaryRow('Coupon Discount', '- ${rupees(discount)}',
                              color: MMColors.terracotta),
                        ],
                        const Divider(height: 24),
                        _summaryRow('Total Payable', rupees(totalAmount), bold: true, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Place Order Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _placing ? null : () => _placeOrder(c),
                    child: _placing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                              SizedBox(width: 12),
                              Text('Placing Order…'),
                            ],
                          )
                        : Text(
                            'Confirm & Place Order — ${rupees(totalAmount)}',
                            style: sans(16, weight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _fulfillmentOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? MMColors.sageLight : MMColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? MMColors.deepOlive : MMColors.borderLight,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? MMColors.deepOlive : MMColors.textMuted, size: 24),
            const SizedBox(height: 8),
            Text(title, style: sans(14, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: sans(12, color: MMColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool bold = false, double size = 14, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: sans(size,
              weight: bold ? FontWeight.w700 : FontWeight.w400,
              color: color ?? MMColors.textSecondary),
        ),
        Text(
          value,
          style: sans(size,
              weight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? (bold ? MMColors.deepOlive : MMColors.textPrimary)),
        ),
      ],
    );
  }
}
