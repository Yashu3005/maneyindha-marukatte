import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class BusinessScreen extends ConsumerStatefulWidget {
  final String id;
  const BusinessScreen({super.key, required this.id});
  @override
  ConsumerState<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends ConsumerState<BusinessScreen> {
  String _productQuery = '';

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(businessProvider(widget.id));
    final products = ref.watch(productsProvider(widget.id));
    final reviews = ref.watch(businessReviewsProvider(widget.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Shop link copied to clipboard')),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: business.when(
        loading: () => const LoadingView(message: 'Loading shop…'),
        error: (e, _) => ErrorView(
          message: 'Could not load this shop.',
          onRetry: () => ref.invalidate(businessProvider(widget.id)),
        ),
        data: (b) {
          final rating = (b['rating'] as Map?) ?? {};
          final address = (b['address'] as Map?) ?? {};
          final experience = b['yearsOfExperience']?.toString();
          final category = b['category'];
          final categoryName = category is Map ? category['name']?.toString() : category?.toString();

          return ResponsiveContainer(
            maxWidth: 1100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ListView(
              children: [
                // Shop Banner & Header Card
                Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: MMColors.borderLight, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: NetImage(b['bannerUrl']?.toString()),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    b['name']?.toString() ?? '',
                                    style: serif(24, weight: FontWeight.w800),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: MMColors.sageLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified_rounded,
                                          size: 16, color: MMColors.deepOlive),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Verified Seller',
                                        style: sans(12,
                                            weight: FontWeight.w700,
                                            color: MMColors.deepOlive),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Tags / Meta Row
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (categoryName != null)
                                  Chip(
                                    label: Text(categoryName),
                                    avatar: const Icon(Icons.category_outlined, size: 14),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (experience != null)
                                  Chip(
                                    label: Text('$experience experience'),
                                    avatar: const Icon(Icons.timeline_rounded, size: 14),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                RatingBadge(rating: rating),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Description
                            Text(
                              b['description']?.toString() ?? 'Home-based entrepreneur in Bengaluru.',
                              style: sans(14, color: MMColors.textSecondary, height: 1.4),
                            ),
                            const SizedBox(height: 10),

                            // Address
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined,
                                    size: 16, color: MMColors.terracotta),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    [address['line1'], address['city']]
                                        .where((x) => x != null && x.toString().isNotEmpty)
                                        .join(', '),
                                    style: sans(13, color: MMColors.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Shop Search & Products Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Products from this Shop', style: serif(20, weight: FontWeight.w700)),
                    if (products.asData != null)
                      Text(
                        '${products.asData!.value.length} items',
                        style: sans(13, color: MMColors.textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                TextField(
                  onChanged: (v) => setState(() => _productQuery = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: 'Search products in this shop…',
                  ),
                ),
                const SizedBox(height: 16),

                // Products Grid
                products.when(
                  loading: () => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Breakpoints.gridColumns(context),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: 4,
                    itemBuilder: (_, __) => const ProductCardSkeleton(),
                  ),
                  error: (e, _) => ErrorView(
                    message: 'Could not load products.',
                    onRetry: () => ref.invalidate(productsProvider(widget.id)),
                  ),
                  data: (items) {
                    var list = List<Map<String, dynamic>>.from(items);
                    if (_productQuery.isNotEmpty) {
                      list = list.where((p) {
                        final name = p['name']?.toString().toLowerCase() ?? '';
                        return name.contains(_productQuery);
                      }).toList();
                    }

                    if (list.isEmpty) {
                      return EmptyView(
                        message: _productQuery.isNotEmpty
                            ? 'No products match "$_productQuery"'
                            : 'No products listed yet.',
                        subtitle: 'Check back soon as this seller prepares fresh items!',
                        icon: Icons.inventory_2_outlined,
                      );
                    }

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: Breakpoints.gridColumns(context),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: list.length,
                      itemBuilder: (_, i) => ProductCard(product: list[i]),
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Reviews Section
                Text('Customer Reviews', style: serif(20, weight: FontWeight.w700)),
                const SizedBox(height: 12),
                reviews.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => const SizedBox(),
                  data: (rvs) {
                    if (rvs.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No reviews yet. Be the first to order and review this shop!',
                            style: sans(14, color: MMColors.textSecondary),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: rvs.map((rv) {
                        final customer = (rv['customer'] as Map?) ?? {};
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: MMColors.sage,
                                      backgroundImage: customer['avatarUrl'] != null
                                          ? NetworkImage(customer['avatarUrl'].toString())
                                          : null,
                                      child: customer['avatarUrl'] == null
                                          ? const Icon(Icons.person, size: 18)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        customer['name']?.toString() ?? 'Verified Customer',
                                        style: sans(14, weight: FontWeight.w600),
                                      ),
                                    ),
                                    RatingBadge(rating: {'avg': rv['rating'], 'count': 1}),
                                  ],
                                ),
                                if (rv['comment'] != null && rv['comment'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    rv['comment'].toString(),
                                    style: sans(14, color: MMColors.textSecondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}
