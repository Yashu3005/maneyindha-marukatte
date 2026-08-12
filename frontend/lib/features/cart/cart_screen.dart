import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _coupon = TextEditingController();

  Future<void> _updateQty(String productId, int quantity) async {
    try {
      await ApiClient.dio.patch('/cart/items',
          data: {'productId': productId, 'quantity': quantity});
      ref.invalidate(cartProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _applyCoupon() async {
    try {
      await ApiClient.dio.post('/cart/coupon', data: {'code': _coupon.text.trim()});
      ref.invalidate(cartProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.push('/login'),
            child: const Text('Sign in to see your cart'),
          ),
        ),
      );
    }

    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: cart.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: apiError(e), onRetry: () => ref.invalidate(cartProvider)),
        data: (c) {
          final items = (c['items'] as List?) ?? [];
          final totals = (c['totals'] as Map?) ?? {};
          if (items.isEmpty) {
            return const EmptyView(message: 'Your cart is empty.\nAdd something delicious!');
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ...items.map((raw) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    final product = Map<String, dynamic>.from(item['product'] as Map);
                    final qty = (item['quantity'] ?? 1) as int;
                    final images = (product['images'] as List?) ?? [];
                    return Card(
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(width: 56, height: 56,
                              child: NetImage(images.isNotEmpty ? images.first.toString() : null)),
                        ),
                        title: Text(product['name']?.toString() ?? ''),
                        subtitle: Text(rupees(product['price'])),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.remove),
                              onPressed: () => _updateQty(product['_id'].toString(), qty - 1)),
                          Text('$qty'),
                          IconButton(icon: const Icon(Icons.add),
                              onPressed: () => _updateQty(product['_id'].toString(), qty + 1)),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(controller: _coupon,
                          decoration: const InputDecoration(
                              labelText: 'Coupon code', hintText: 'WELCOME10')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(onPressed: _applyCoupon, child: const Text('Apply')),
                  ]),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        _row('Subtotal', rupees(totals['subtotal'])),
                        if ((totals['discount'] ?? 0) != 0)
                          _row('Discount', '- ${rupees(totals['discount'])}'),
                        const Divider(),
                        _row('Total', rupees(totals['total'] ?? totals['subtotal']), bold: true),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push('/checkout'),
                    child: const Text('Proceed to checkout'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label, style: style), Text(value, style: style)]),
    );
  }
}
