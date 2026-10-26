import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class ProductScreen extends ConsumerStatefulWidget {
  final String id;
  const ProductScreen({super.key, required this.id});
  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  bool _adding = false;
  int _qty = 1;

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.push('/login');
      return;
    }
    setState(() => _adding = true);
    try {
      await ApiClient.dio.post('/cart/items',
          data: {'productId': widget.id, 'quantity': _qty});
      ref.invalidate(cartProvider);
      // Read the fresh cart so the pop-up can show what is in it now (best effort).
      Map<String, dynamic>? cart;
      try {
        cart = await ref.read(cartProvider.future);
      } catch (_) {}
      if (mounted) await _showAddedSheet(product, cart);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _showAddedSheet(Map<String, dynamic> p, Map<String, dynamic>? cart) {
    final images = (p['images'] as List?) ?? [];
    final items = (cart?['items'] as List?) ?? const [];
    final count = items.fold<int>(0, (sum, raw) => sum + (((raw as Map)['quantity'] ?? 0) as num).toInt());
    final totals = (cart?['totals'] as Map?) ?? const {};
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 64, height: 64,
                    child: NetImage(images.isNotEmpty ? images.first.toString() : null)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.check_circle, color: MMColors.moss, size: 18),
                    const SizedBox(width: 6),
                    Text('Added to cart', style: serif(16)),
                  ]),
                  const SizedBox(height: 2),
                  Text('$_qty × ${p['name'] ?? ''}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            if (cart != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MMColors.blush, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Your cart · $count item${count == 1 ? '' : 's'}'),
                  Text(rupees(totals['total'] ?? totals['subtotal']),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Keep shopping'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () { Navigator.pop(ctx); context.push('/cart'); },
                  child: const Text('View cart'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Product')),
      body: product.when(
        loading: () => const LoadingView(),
        error: (e, _) => const ErrorView(message: 'Could not load this product.'),
        data: (p) {
          final images = (p['images'] as List?) ?? [];
          final business = p['business'];
          final stock = ((p['stock'] ?? 0) as num).toInt();
          final price = p['price'];
          final inStock = stock > 0;
          return Column(children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: softShadow(0.14),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(height: 300, width: double.infinity,
                              child: NetImage(images.isNotEmpty ? images.first.toString() : null)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Text(p['name']?.toString() ?? '', style: serif(26))),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: MMColors.deepOlive, borderRadius: BorderRadius.circular(14)),
                          child: Text(rupees(price),
                              style: const TextStyle(
                                  color: MMColors.cream, fontWeight: FontWeight.w700, fontSize: 18)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (business is Map)
                          Chip(
                            avatar: const Icon(Icons.storefront, size: 16),
                            label: Text('By ${business['name']}'),
                          ),
                        Chip(
                          avatar: Icon(inStock ? Icons.check_circle : Icons.cancel,
                              size: 16, color: inStock ? MMColors.moss : Colors.red),
                          label: Text(inStock ? 'In stock · $stock' : 'Out of stock'),
                        ),
                        RatingBadge(rating: p['rating']),
                      ]),
                      const SizedBox(height: 16),
                      SoftCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('About this item', style: serif(16)),
                          const SizedBox(height: 6),
                          Text((p['description']?.toString().isNotEmpty ?? false)
                              ? p['description'].toString()
                              : 'Made fresh by a local home entrepreneur.'),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // sticky action bar
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
                        QuantityStepper(
                          value: _qty, max: inStock ? (stock > 50 ? 50 : stock) : 1, enabled: inStock && !_adding,
                          onChanged: (v) => setState(() => _qty = v),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (inStock && !_adding) ? () => _addToCart(Map<String, dynamic>.from(p)) : null,
                            icon: _adding
                                ? const SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: MMColors.cream))
                                : const Icon(Icons.add_shopping_cart),
                            label: Text(_adding ? 'Adding…' : 'Add to cart'),
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
}
