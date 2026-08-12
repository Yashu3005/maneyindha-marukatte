import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';

class ProductScreen extends ConsumerStatefulWidget {
  final String id;
  const ProductScreen({super.key, required this.id});
  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  bool _adding = false;

  Future<void> _addToCart() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.push('/login');
      return;
    }
    setState(() => _adding = true);
    try {
      await ApiClient.dio.post('/cart/items',
          data: {'productId': widget.id, 'quantity': 1});
      ref.invalidate(cartProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Added to cart — find it in the Cart tab'),
            duration: Duration(seconds: 2),
          ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Product')),
      body: product.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: 'Could not load this product.'),
        data: (p) {
          final images = (p['images'] as List?) ?? [];
          final business = p['business'];
          final stock = (p['stock'] ?? 0) as num;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(height: 280, width: double.infinity,
                        child: NetImage(images.isNotEmpty ? images.first.toString() : null)),
                  ),
                  const SizedBox(height: 16),
                  Text(p['name']?.toString() ?? '',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(rupees(p['price']),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (business is Map)
                    Text('By ${business['name']}',
                        style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  Text(p['description']?.toString() ?? ''),
                  const SizedBox(height: 12),
                  Text(stock > 0 ? 'In stock: $stock' : 'Out of stock',
                      style: TextStyle(
                          color: stock > 0 ? Colors.teal : Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: (stock > 0 && !_adding) ? _addToCart : null,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: Text(_adding ? 'Adding…' : 'Add to cart'),
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
