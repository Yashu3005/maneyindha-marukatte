import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class ProductScreen extends ConsumerStatefulWidget {
  final String id;
  const ProductScreen({super.key, required this.id});
  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  int _quantity = 1;
  int _selectedImage = 0;
  bool _adding = false;
  bool _togglingWishlist = false;

  Future<void> _addToCart(num stock) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.push('/login');
      return;
    }

    if (stock <= 0) return;

    setState(() => _adding = true);
    try {
      await ApiClient.dio.post(
        '/cart/items',
        data: {'productId': widget.id, 'quantity': _quantity},
      );
      ref.invalidate(cartProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('Added $_quantity to your cart'),
              ],
            ),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View Cart',
              textColor: MMColors.terracottaLight,
              onPressed: () => context.push('/cart'),
            ),
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
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _toggleWishlist() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.push('/login');
      return;
    }

    setState(() => _togglingWishlist = true);
    try {
      final res = await ApiClient.dio.post(
        '/wishlist/products',
        data: {'productId': widget.id},
      );
      ref.invalidate(wishlistProvider);
      final inWishlist = res.data['data']?['inWishlist'] == true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(inWishlist
                ? 'Saved to your Wishlist ❤️'
                : 'Removed from your Wishlist'),
            duration: const Duration(seconds: 2),
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
      if (mounted) setState(() => _togglingWishlist = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productProvider(widget.id));
    final isDesktop = Breakpoints.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          IconButton(
            icon: _togglingWishlist
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.favorite_border_rounded),
            tooltip: 'Save to Wishlist',
            onPressed: _toggleWishlist,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Product link copied to clipboard')),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: productAsync.when(
        loading: () => const LoadingView(message: 'Loading product details…'),
        error: (e, _) => ErrorView(
          message: 'Could not load this product.',
          onRetry: () => ref.invalidate(productProvider(widget.id)),
        ),
        data: (p) {
          final images = (p['images'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final business = p['business'];
          final stock = (p['stock'] ?? 0) as num;
          final rating = (p['rating'] as Map?) ?? {};
          final hasBusiness = business is Map;

          final mainImageUrl = images.isNotEmpty
              ? (_selectedImage < images.length ? images[_selectedImage] : images.first)
              : null;

          return ResponsiveContainer(
            maxWidth: 1100,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Gallery & Images
                      Expanded(
                        flex: 5,
                        child: _imageGallery(mainImageUrl, images),
                      ),
                      const SizedBox(width: 48),
                      // Right Column: Details & Actions
                      Expanded(
                        flex: 6,
                        child: _productDetails(p, business, hasBusiness, stock, rating),
                      ),
                    ],
                  )
                : ListView(
                    children: [
                      _imageGallery(mainImageUrl, images),
                      const SizedBox(height: 24),
                      _productDetails(p, business, hasBusiness, stock, rating),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _imageGallery(String? mainImageUrl, List<String> images) {
    return Column(
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: MMColors.borderLight, width: 1.5),
          ),
          child: AspectRatio(
            aspectRatio: 1.1,
            child: NetImage(mainImageUrl, fit: BoxFit.cover),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final isSelected = _selectedImage == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedImage = i),
                  child: Container(
                    width: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? MMColors.terracotta : MMColors.border,
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: NetImage(images[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _productDetails(
    Map<String, dynamic> p,
    dynamic business,
    bool hasBusiness,
    num stock,
    Map rating,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Seller link banner
        if (hasBusiness)
          InkWell(
            onTap: () => context.push('/business/${business['_id']}'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_rounded, size: 18, color: MMColors.olive),
                  const SizedBox(width: 6),
                  Text(
                    business['name']?.toString() ?? '',
                    style: sans(13, weight: FontWeight.w600, color: MMColors.olive),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: MMColors.olive),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),

        // Product Name
        Text(
          p['name']?.toString() ?? '',
          style: serif(28, weight: FontWeight.w800, height: 1.2),
        ),
        const SizedBox(height: 12),

        // Rating & Reviews row
        Row(
          children: [
            RatingBadge(rating: rating),
            const SizedBox(width: 12),
            Text(
              stock > 0 ? 'Freshly made to order' : 'Out of stock',
              style: sans(
                13,
                weight: FontWeight.w600,
                color: stock > 0 ? MMColors.olive : const Color(0xFFBA1A1A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Price
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              rupees(p['price']),
              style: sans(32, weight: FontWeight.w900, color: MMColors.deepOlive),
            ),
            const SizedBox(width: 8),
            Text('(inclusive of all taxes)', style: sans(12, color: MMColors.textMuted)),
          ],
        ),
        const SizedBox(height: 20),

        // Description
        Text('About this creation', style: serif(18, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          p['description']?.toString() ?? 'No description provided by the artisan.',
          style: sans(15, color: MMColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),

        // Trust Signals
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MMColors.sageLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _trustItem(Icons.home_work_outlined, '100% Home-made by certified local women'),
              const SizedBox(height: 8),
              _trustItem(Icons.verified_outlined, 'Sanitary preparation & quality tested'),
              const SizedBox(height: 8),
              _trustItem(Icons.delivery_dining_outlined, 'Fresh local doorstep delivery'),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Quantity Stepper + Add To Cart Button
        if (stock > 0) ...[
          Row(
            children: [
              Text('Quantity:', style: sans(15, weight: FontWeight.w600)),
              const SizedBox(width: 16),
              Container(
                decoration: BoxDecoration(
                  color: MMColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: MMColors.border),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    Text(
                      '$_quantity',
                      style: sans(16, weight: FontWeight.w700),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: _quantity < stock ? () => setState(() => _quantity++) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Max stock: $stock',
                style: sans(12, color: MMColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: stock > 0 ? MMColors.deepOlive : Colors.grey,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: (stock > 0 && !_adding) ? () => _addToCart(stock) : null,
            icon: _adding
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.add_shopping_cart_rounded),
            label: Text(
              _adding
                  ? 'Adding to Cart…'
                  : (stock > 0 ? 'Add to Cart — ${rupees(p['price'] * _quantity)}' : 'Sold Out'),
              style: sans(16, weight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _trustItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: MMColors.deepOlive),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: sans(13, color: MMColors.textPrimary)),
        ),
      ],
    );
  }
}
