import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isSelfPickup = false;
  String _paymentMethod = 'cod'; // 'online' or 'cod'
  final _orderNote = TextEditingController();
  bool _processing = false;
  Map<String, dynamic>? _placedOrder;

  Future<void> _processCheckout(Map<String, dynamic> checkoutData) async {
    final selectedAddress = ref.read(selectedDeliveryAddressProvider);
    if (!_isSelfPickup && selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or add a delivery address')),
      );
      return;
    }

    setState(() => _processing = true);

    try {
      final items = (checkoutData['items'] as List).map((it) {
        return {
          'productId': it['productId'],
          'quantity': it['quantity'],
          'customization': it['customization'],
        };
      }).toList();

      final res = await ApiClient.dio.post('/orders', data: {
        'businessId': checkoutData['businessId'],
        'items': items,
        'isSelfPickup': _isSelfPickup,
        'deliveryAddress': _isSelfPickup ? null : selectedAddress,
        'notes': _orderNote.text.trim(),
        'paymentMethod': _paymentMethod,
      });

      ref.invalidate(cartProvider);
      ref.invalidate(ordersProvider);

      setState(() {
        _placedOrder = Map<String, dynamic>.from(res.data['data'] as Map);
        _processing = false;
      });
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If order was successfully placed, display the Order Placed Successfully screen
    if (_placedOrder != null) {
      final o = _placedOrder!;
      final orderNumber = o['orderNumber'] ?? '#MM1001';
      final total = o['amounts']?['total'] ?? 0;
      final isPickup = o['isSelfPickup'] == true;

      return Scaffold(
        backgroundColor: MMColors.warmIvory,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 48, color: Colors.green),
                  ),
                  const SizedBox(height: 24),
                  Text('Order Placed Successfully!',
                      style: serif(24, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('Your order has been placed and received by the artisan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MMColors.textSecondary, fontSize: 14)),
                  const SizedBox(height: 24),
                  Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: MMColors.sage, width: 0.8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Order ID', style: TextStyle(color: MMColors.textSecondary)),
                              Text(orderNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Amount', style: TextStyle(color: MMColors.textSecondary)),
                              Text(rupees(total),
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: MMColors.primaryGreen)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Delivery Method', style: TextStyle(color: MMColors.textSecondary)),
                              Text(isPickup ? 'Self Pickup' : 'Home Delivery',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const Divider(height: 16),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Estimated Delivery', style: TextStyle(color: MMColors.textSecondary)),
                              Text('Today before 5:30 PM', style: TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: MMColors.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => context.go('/orders'),
                      child: const Text('View Order in My Orders',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: MMColors.primaryGreen),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => context.go('/app'),
                      child: const Text('Continue Shopping',
                          style: TextStyle(fontWeight: FontWeight.w700, color: MMColors.primaryGreen)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final state = GoRouterState.of(context);
    final checkoutData = (state.extra as Map?) ?? {};
    final items = (checkoutData['items'] as List?) ?? [];
    final selectedAddress = ref.watch(selectedDeliveryAddressProvider);
    final addressesAsync = ref.watch(addressesProvider);

    // Initialize default address if available and not selected
    addressesAsync.whenData((list) {
      if (selectedAddress == null && list.isNotEmpty) {
        final def = list.firstWhere((a) => a['isDefault'] == true, orElse: () => list.first);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(selectedDeliveryAddressProvider.notifier).state = def;
        });
      }
    });

    final num subtotal = checkoutData['subtotal'] ?? 0;
    final num deliveryFee = _isSelfPickup ? 0 : (checkoutData['deliveryFee'] ?? 30);
    final num total = subtotal + deliveryFee;

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      appBar: AppBar(
        backgroundColor: MMColors.warmIvory,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MMColors.primaryGreen),
          onPressed: () => context.pop(),
        ),
        title: Text('Checkout', style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Delivery Address Card
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: MMColors.sage, width: 0.8),
            ),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: MMColors.primaryGreen, size: 20),
                          const SizedBox(width: 6),
                          Text('Delivery Address',
                              style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                        ],
                      ),
                      TextButton(
                        onPressed: () => context.push('/addresses'),
                        child: const Text('Change Address',
                            style: TextStyle(color: MMColors.primaryGreen, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (selectedAddress != null) ...[
                    Text(selectedAddress['label'] ?? 'Home',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(selectedAddress['line1'] ?? '', style: const TextStyle(fontSize: 13)),
                    Text('${selectedAddress['city'] ?? ''}, ${selectedAddress['pincode'] ?? ''}',
                        style: const TextStyle(color: MMColors.textSecondary, fontSize: 13)),
                  ] else ...[
                    const Text('No address selected. Tap Change Address to add one.',
                        style: TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Delivery Method
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: MMColors.sage, width: 0.8),
            ),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delivery Method',
                      style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  RadioListTile<bool>(
                    activeColor: MMColors.primaryGreen,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Home Delivery', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('₹30 Delivery Fee • Delivered directly to your door'),
                    value: false,
                    groupValue: _isSelfPickup,
                    onChanged: (val) => setState(() => _isSelfPickup = val ?? false),
                  ),
                  RadioListTile<bool>(
                    activeColor: MMColors.primaryGreen,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Self Pickup', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('FREE • Pickup from artisan’s home kitchen or studio'),
                    value: true,
                    groupValue: _isSelfPickup,
                    onChanged: (val) => setState(() => _isSelfPickup = val ?? false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Selected Products Preview
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: MMColors.sage, width: 0.8),
            ),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Selected Products (${items.length})',
                      style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ...items.map((it) {
                    final images = (it['images'] as List?) ?? [];
                    final img = images.isNotEmpty ? images.first.toString() : null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(width: 44, height: 44, child: NetImage(img)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it['name']?.toString() ?? 'Item',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text('Qty: ${it['quantity']} • ${rupees(it['price'])}',
                                    style: const TextStyle(fontSize: 12, color: MMColors.textSecondary)),
                                if (it['customization'] != null &&
                                    it['customization'].toString().isNotEmpty)
                                  Text('Note: ${it['customization']}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: MMColors.primaryGreen)),
                              ],
                            ),
                          ),
                          Text(rupees((it['price'] ?? 0) * (it['quantity'] ?? 1)),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Order Note (Optional)
          TextField(
            controller: _orderNote,
            decoration: const InputDecoration(
              labelText: 'Order Note (Optional)',
              hintText: 'Please write any instructions for the artisan...',
            ),
          ),
          const SizedBox(height: 16),

          // Payment Method
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: MMColors.sage, width: 0.8),
            ),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment Method',
                      style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    activeColor: MMColors.primaryGreen,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cash on Delivery (COD)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Pay with cash or UPI on delivery / pickup'),
                    value: 'cod',
                    groupValue: _paymentMethod,
                    onChanged: (val) => setState(() => _paymentMethod = val ?? 'cod'),
                  ),
                  RadioListTile<String>(
                    activeColor: MMColors.primaryGreen,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Online Payment', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('UPI, Google Pay, Cards & Net Banking'),
                    value: 'online',
                    groupValue: _paymentMethod,
                    onChanged: (val) => setState(() => _paymentMethod = val ?? 'online'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Order Summary Card
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: MMColors.sage, width: 0.8),
            ),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal', style: TextStyle(color: MMColors.textSecondary)),
                      Text(rupees(subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delivery Charge', style: TextStyle(color: MMColors.textSecondary)),
                      Text(_isSelfPickup ? 'FREE' : rupees(deliveryFee),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _isSelfPickup ? Colors.green : MMColors.textPrimary)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Amount',
                          style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                      Text(rupees(total),
                          style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Place Order Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MMColors.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _processing ? null : () => _processCheckout(Map<String, dynamic>.from(checkoutData)),
              child: _processing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Processing Payment & Order...'),
                      ],
                    )
                  : Text(
                      _paymentMethod == 'online'
                          ? 'Pay & Place Order (${rupees(total)})'
                          : 'Place Order (${rupees(total)})',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
