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
        // Capture the router object — it stays valid even if this screen
        // is popped before the action is tapped (the old bug).
        final router = GoRouter.of(context);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
            content: const Text('Added to cart 🛒'),
            action: SnackBarAction(
              label: 'View cart',
              onPressed: () => router.push('/cart'),
            ),
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
                  const SizedBox(height: 20),
                  if (business is Map) _SellerCard(business: business),
                  const SizedBox(height: 16),
                  _ReviewsSection(productId: widget.id, rating: p['rating']),
                  const SizedBox(height: 20),
                  Consumer(builder: (c, r, _) {
                    final reviews = r.watch(productReviewsProvider(widget.id));
                    return reviews.when(
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => const SizedBox.shrink(),
                      data: (items) {
                        if (items.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Reviews (${items.length})',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            ...items.take(5).map((rv) {
                              final customer = (rv['customer'] as Map?) ?? {};
                              return Card(
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundImage: customer['avatarUrl'] != null
                                        ? NetworkImage(customer['avatarUrl'].toString())
                                        : null,
                                    child: customer['avatarUrl'] == null
                                        ? const Icon(Icons.person, size: 16)
                                        : null,
                                  ),
                                  title: Row(children: [
                                    Text('${'★' * ((rv['rating'] ?? 0) as int)}',
                                        style: const TextStyle(
                                            color: Color(0xFFD9922E))),
                                    const SizedBox(width: 8),
                                    Text(customer['name']?.toString() ?? '',
                                        style: const TextStyle(fontSize: 13)),
                                    if (rv['isVerifiedPurchase'] == true) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.verified,
                                          size: 14, color: Colors.teal),
                                    ],
                                  ]),
                                  subtitle: (rv['comment'] ?? '').toString().isEmpty
                                      ? null
                                      : Text(rv['comment'].toString()),
                                ),
                              );
                            }),
                            const SizedBox(height: 12),
                          ],
                        );
                      },
                    );
                  }),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (stock > 0 && !_adding) ? _addToCart : null,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: Text(_adding ? 'Adding…' : 'Add to cart'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.outlined(
                      tooltip: 'Save to wishlist',
                      icon: const Icon(Icons.favorite_outline),
                      onPressed: () async {
                        final auth = ref.read(authProvider);
                        if (!auth.isLoggedIn) { context.push('/login'); return; }
                        try {
                          final res = await ApiClient.dio.post('/wishlist/products',
                              data: {'productId': widget.id});
                          final saved = (res.data['data'] as Map)['inWishlist'] == true;
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(saved ? 'Saved to wishlist ♡' : 'Removed from wishlist'),
                                duration: const Duration(seconds: 2)));
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(apiError(e))));
                          }
                        }
                      },
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


class _SellerCard extends StatelessWidget {
  final Map business;
  const _SellerCard({required this.business});

  @override
  Widget build(BuildContext context) {
    final owner = (business['owner'] as Map?) ?? {};
    final rating = (business['rating'] as Map?) ?? {};
    final address = (business['address'] as Map?) ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('About the seller',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 52, height: 52,
                  child: NetImage(business['logoUrl']?.toString())),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(business['name']?.toString() ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, size: 16, color: Colors.teal),
                ]),
                Text(
                  (rating['count'] ?? 0) == 0
                      ? 'New shop'
                      : '★ ${rating['avg']} (${rating['count']} reviews)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
            OutlinedButton(
              onPressed: () =>
                  context.push('/business/${business['_id']}'),
              child: const Text('Visit shop'),
            ),
          ]),
          const SizedBox(height: 10),
          if ((business['description'] ?? '').toString().isNotEmpty)
            Text(business['description'].toString()),
          const SizedBox(height: 6),
          Text(
            'By ${owner['name'] ?? 'a local entrepreneur'}'
            '${business['yearsOfExperience'] != null ? ' · ${business['yearsOfExperience']} experience' : ''}'
            '${address['city'] != null ? ' · ${address['line1'] ?? ''}, ${address['city']}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}

class _ReviewsSection extends ConsumerWidget {
  final String productId;
  final dynamic rating;
  const _ReviewsSection({required this.productId, this.rating});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(productReviewsProvider(productId));
    final r = rating is Map ? rating as Map : const {};
    final count = (r['count'] ?? 0) as num;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        count == 0
            ? 'Reviews'
            : 'Reviews · ★ ${r['avg']} ($count)',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      reviews.when(
        loading: () => const LoadingView(),
        error: (e, _) => const SizedBox.shrink(),
        data: (items) => items.isEmpty
            ? const Text('No reviews yet — order it and be the first! ⭐')
            : Column(
                children: items.take(5).map((rv) {
                  final customer = (rv['customer'] as Map?) ?? {};
                  final stars = (rv['rating'] ?? 0) as num;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: customer['avatarUrl'] != null
                            ? NetworkImage(customer['avatarUrl'].toString())
                            : null,
                        child: customer['avatarUrl'] == null
                            ? const Icon(Icons.person, size: 18)
                            : null,
                      ),
                      title: Row(children: [
                        Text('★' * stars.toInt() + '☆' * (5 - stars.toInt()),
                            style: const TextStyle(color: Color(0xFFD9922E))),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(customer['name']?.toString() ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (rv['isVerifiedPurchase'] == true) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_user,
                              size: 13, color: Colors.teal),
                        ],
                      ]),
                      subtitle: (rv['comment'] ?? '').toString().isEmpty
                          ? null
                          : Text(rv['comment'].toString()),
                    ),
                  );
                }).toList(),
              ),
      ),
    ]);
  }
}
