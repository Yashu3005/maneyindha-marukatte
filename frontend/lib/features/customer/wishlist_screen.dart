import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  Future<void> _removeFromWishlist(BuildContext context, WidgetRef ref, String productId) async {
    try {
      await ApiClient.dio.post('/wishlist/products', data: {'productId': productId});
      ref.invalidate(wishlistProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Removed from Wishlist'),
            duration: Duration(seconds: 2),
          ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _addToCart(BuildContext context, WidgetRef ref, String productId) async {
    try {
      await ApiClient.dio.post('/cart/items', data: {'productId': productId, 'quantity': 1});
      ref.invalidate(cartProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Added to Cart 🛍️'),
            duration: Duration(seconds: 2),
          ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlistAsync = ref.watch(wishlistProvider);

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      appBar: AppBar(
        backgroundColor: MMColors.warmIvory,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MMColors.primaryGreen),
          onPressed: () => context.pop(),
        ),
        title: Text('Wishlist', style: serif(20, color: MMColors.primaryGreen)),
        elevation: 0,
      ),
      body: wishlistAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Could not load Wishlist.',
          onRetry: () => ref.invalidate(wishlistProvider),
        ),
        data: (data) {
          final products = (data['products'] as List?) ?? [];
          final count = products.length;

          if (products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite_border, size: 72, color: MMColors.secondaryGreen),
                    const SizedBox(height: 16),
                    Text('Your Wishlist is Empty',
                        style: serif(22, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Save products you like\nfor later.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MMColors.textSecondary, fontSize: 15)),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: MMColors.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => context.go('/app'),
                      child: const Text('Continue Shopping'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              Text('❤️ My Wishlist',
                  style: serif(24, color: MMColors.primaryGreen, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('$count ${count == 1 ? 'Item' : 'Items'}',
                  style: const TextStyle(color: MMColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.65,
                ),
                itemCount: products.length,
                itemBuilder: (ctx, i) {
                  final p = Map<String, dynamic>.from(products[i] as Map);
                  final pId = p['_id']?.toString() ?? '';
                  final images = (p['images'] as List?) ?? [];
                  final firstImage = images.isNotEmpty ? images.first.toString() : null;
                  final rating = (p['rating'] is Map)
                      ? (p['rating']['avg'] ?? 4.8)
                      : 4.8;
                  final storeName = (p['business'] is Map)
                      ? p['business']['name']
                      : 'Local Artisan';

                  return Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: MMColors.sage, width: 0.8),
                    ),
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push('/product/$pId'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: NetImage(firstImage),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Material(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(6),
                                      icon: const Icon(Icons.favorite, color: Colors.red, size: 20),
                                      onPressed: () => _removeFromWishlist(context, ref, pId),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['name']?.toString() ?? 'Product',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: MMColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  rupees(p['price']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: MMColors.primaryGreen,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.star, size: 13, color: MMColors.accentGold),
                                    const SizedBox(width: 3),
                                    Text('$rating',
                                        style: const TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$storeName',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11, color: MMColors.textSecondary),
                                      ),
                                    ),
                                    const Icon(Icons.verified, size: 13, color: MMColors.primaryGreen),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 34,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: MMColors.primaryGreen),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                      padding: EdgeInsets.zero,
                                    ),
                                    onPressed: () => _addToCart(context, ref, pId),
                                    child: const Text('Add',
                                        style: TextStyle(
                                            color: MMColors.primaryGreen,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
