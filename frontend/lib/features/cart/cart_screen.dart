import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _coupon = TextEditingController();
  bool _busy = false;
  // Rows swiped away are hidden at once (a Dismissible must leave the tree synchronously),
  // then unhidden when the server has answered.
  final Set<String> _hidden = {};

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _updateQty(String productId, int quantity) async {
    setState(() => _busy = true);
    try {
      await ApiClient.dio.patch('/cart/items',
          data: {'productId': productId, 'quantity': quantity});
      ref.invalidate(cartProvider);
    } catch (e) {
      _toast(apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String productId, String name) async {
    setState(() => _hidden.add(productId));
    await _updateQty(productId, 0);
    try { await ref.read(cartProvider.future); } catch (_) {} // wait for the fresh cart before unhiding
    if (!mounted) return;
    setState(() => _hidden.remove(productId));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$name removed'),
        action: SnackBarAction(
          label: 'Undo',
          textColor: MMColors.marigold,
          onPressed: () async {
            try {
              await ApiClient.dio.post('/cart/items', data: {'productId': productId, 'quantity': 1});
              ref.invalidate(cartProvider);
            } catch (e) {
              _toast(apiError(e));
            }
          },
        ),
      ));
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty your cart?'),
        content: const Text('All items will be removed from your cart.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep items')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Empty cart')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ApiClient.dio.delete('/cart');
      ref.invalidate(cartProvider);
    } catch (e) {
      _toast(apiError(e));
    }
  }

  Future<void> _applyCoupon() async {
    if (_coupon.text.trim().isEmpty) return;
    try {
      await ApiClient.dio.post('/cart/coupon', data: {'code': _coupon.text.trim()});
      ref.invalidate(cartProvider);
      _toast('Coupon applied');
    } catch (e) {
      _toast(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.shopping_bag_outlined, size: 64, color: MMColors.olive),
              const SizedBox(height: 12),
              Text('Sign in to see your cart', style: serif(20)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('Sign in'),
              ),
            ]),
          ),
        ),
      );
    }

    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cart'),
        actions: [
          if (cart.valueOrNull != null && ((cart.valueOrNull!['items'] as List?) ?? []).isNotEmpty)
            TextButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Empty'),
            ),
        ],
      ),
      body: cart.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: apiError(e), onRetry: () => ref.invalidate(cartProvider)),
        data: (c) {
          final items = ((c['items'] as List?) ?? [])
              .where((raw) => !_hidden.contains(((raw as Map)['product'] as Map)['_id'].toString()))
              .toList();
          final totals = (c['totals'] as Map?) ?? {};
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: const BoxDecoration(color: MMColors.blush, shape: BoxShape.circle),
                    child: const Icon(Icons.shopping_basket_outlined, size: 54, color: MMColors.clay),
                  ),
                  const SizedBox(height: 16),
                  Text('Your cart is empty', style: serif(22)),
                  const SizedBox(height: 6),
                  const Text('Add something delicious from a nearby shop.', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => context.go('/app'),
                    child: const Text('Browse shops'),
                  ),
                ]),
              ),
            );
          }
          final total = totals['total'] ?? totals['subtotal'];
          return Column(children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...items.map((raw) {
                        final item = Map<String, dynamic>.from(raw as Map);
                        final product = Map<String, dynamic>.from(item['product'] as Map);
                        final pid = product['_id'].toString();
                        final name = product['name']?.toString() ?? 'Item';
                        final qty = ((item['quantity'] ?? 1) as num).toInt();
                        final images = (product['images'] as List?) ?? [];
                        return Dismissible(
                          key: ValueKey('cart-$pid'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 22),
                            decoration: BoxDecoration(
                              color: Colors.red.shade400,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          onDismissed: (_) => _remove(pid, name),
                          child: SoftCard(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(width: 68, height: 68,
                                    child: NetImage(images.isNotEmpty ? images.first.toString() : null)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(rupees(product['price']),
                                      style: const TextStyle(color: MMColors.moss, fontWeight: FontWeight.w700)),
                                ]),
                              ),
                              QuantityStepper(
                                value: qty, min: 0, max: 50, enabled: !_busy,
                                onChanged: (v) => v == 0 ? _remove(pid, name) : _updateQty(pid, v),
                              ),
                            ]),
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      SoftCard(
                        child: Row(children: [
                          const Icon(Icons.local_offer_outlined, color: MMColors.clay),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _coupon,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                  hintText: 'Have a coupon code?', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(onPressed: _applyCoupon, child: const Text('Apply')),
                        ]),
                      ),
                      SoftCard(
                        child: Column(children: [
                          _row('Subtotal', rupees(totals['subtotal'])),
                          if ((totals['discount'] ?? 0) != 0)
                            _row('Discount', '- ${rupees(totals['discount'])}', color: MMColors.moss),
                          const Divider(),
                          _row('Total', rupees(total), bold: true),
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
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Row(children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Total', style: TextStyle(fontSize: 12)),
                          Text(rupees(total), style: serif(22)),
                        ]),
                        const SizedBox(width: 20),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : () => context.push('/checkout'),
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Checkout'),
                          ),
                        ),
                      ]),
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

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label, style: style), Text(value, style: style)]),
    );
  }
}
