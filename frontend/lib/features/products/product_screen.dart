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
  int _currentImageIndex = 0;
  final _customizationCtrl = TextEditingController();
  bool _isAdding = false;

  Future<void> _toggleWishlist() async {
    try {
      await ApiClient.dio.post('/wishlist/products', data: {'productId': widget.id});
      ref.invalidate(wishlistProvider);
    } catch (_) {}
  }

  Future<void> _addToCart({bool navigateToCheckout = false, Map<String, dynamic>? product}) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.push('/login');
      return;
    }

    setState(() => _isAdding = true);
    try {
      await ApiClient.dio.post('/cart/items', data: {
        'productId': widget.id,
        'quantity': _quantity,
        'customization': _customizationCtrl.text.trim(),
      });
      ref.invalidate(cartProvider);

      if (navigateToCheckout && product != null) {
        final businessId = product['business']?['_id'] ?? product['business'];
        final price = (product['price'] ?? 0) as num;
        final subtotal = price * _quantity;
        final deliveryFee = product['deliveryOptions']?['deliveryCharge'] ?? 30;

        if (mounted) {
          context.push('/checkout', extra: {
            'businessId': businessId,
            'items': [
              {
                'productId': widget.id,
                'name': product['name'],
                'price': price,
                'quantity': _quantity,
                'customization': _customizationCtrl.text.trim(),
                'images': product['images'],
              }
            ],
            'subtotal': subtotal,
            'deliveryFee': deliveryFee,
            'total': subtotal + deliveryFee,
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(
              content: Text('Added to Cart 🛍️'),
              duration: Duration(seconds: 2),
            ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  void _showReportDialog() {
    String selectedReason = 'Inappropriate content';
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Report Product', style: serif(18, color: MMColors.primaryGreen)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  'Inappropriate content',
                  'Misleading information',
                  'Prohibited item',
                  'Wrong category',
                  'Other',
                ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setDialogState(() => selectedReason = v ?? 'Inappropriate content'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () async {
                try {
                  await ApiClient.dio.post('/products/${widget.id}/report', data: {
                    'reason': selectedReason,
                    'description': descCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Report Submitted Successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productProvider(widget.id));
    final wishlistAsync = ref.watch(wishlistProvider);

    final inWishlist = wishlistAsync.maybeWhen(
      data: (d) => ((d['products'] as List?) ?? [])
          .any((p) => (p is Map ? p['_id'] : p).toString() == widget.id),
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      appBar: AppBar(
        backgroundColor: MMColors.warmIvory,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MMColors.primaryGreen),
          onPressed: () => context.pop(),
        ),
        title: Text('Product Details', style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(
              inWishlist ? Icons.favorite : Icons.favorite_border,
              color: inWishlist ? Colors.red : MMColors.primaryGreen,
            ),
            onPressed: _toggleWishlist,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: MMColors.primaryGreen),
            onSelected: (val) {
              if (val == 'report') _showReportDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('Report Product')),
            ],
          ),
        ],
        elevation: 0,
      ),
      body: productAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Could not load product.',
          onRetry: () => ref.invalidate(productProvider(widget.id)),
        ),
        data: (p) {
          final images = (p['images'] as List?) ?? [];
          if (images.isEmpty) {
            images.add('https://picsum.photos/seed/${widget.id}/600/400');
          }
          final business = (p['business'] as Map?) ?? {};
          final storeName = business['name']?.toString() ?? 'Artisan Store';
          final storeId = business['_id']?.toString() ?? '';
          final stock = (p['stock'] ?? 10) as num;
          final inStock = stock > 0;
          final rating = (p['rating'] is Map) ? (p['rating']['avg'] ?? 4.8) : 4.8;
          final reviewCount = (p['rating'] is Map) ? (p['rating']['count'] ?? 24) : 24;

          final delivery = (p['deliveryOptions'] as Map?) ?? {};
          final homeDelivery = delivery['homeDelivery'] != false;
          final pickup = delivery['pickup'] != false;
          final deliveryCharge = delivery['deliveryCharge'] ?? 30;

          final afterSales = (p['afterSales'] as Map?) ?? {};
          final supportType = afterSales['supportType'] ?? 'replacement_only';
          final supportWindow = afterSales['supportWindow'] ?? '3 Days';
          final returnRequired = afterSales['returnRequired'] == true;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // Product Image Carousel
              SizedBox(
                height: 260,
                child: PageView.builder(
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _currentImageIndex = i),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: NetImage(images[i].toString()),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (images.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) {
                    final isCurrent = i == _currentImageIndex;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isCurrent ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isCurrent ? MMColors.primaryGreen : MMColors.sage,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 16),

              // Title, Price & Stock
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      p['name']?.toString() ?? '',
                      style: serif(22, color: MMColors.textPrimary, weight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    rupees(p['price']),
                    style: serif(22, color: MMColors.primaryGreen, weight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Rating and Stock status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: MMColors.accentGold,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text('$rating',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(width: 4),
                        const Icon(Icons.star, size: 12, color: Colors.white),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('($reviewCount Reviews)',
                      style: const TextStyle(color: MMColors.textSecondary, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: inStock ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: inStock ? Colors.green.shade300 : Colors.red.shade300, width: 0.8),
                    ),
                    child: Text(
                      inStock ? 'In Stock ($stock)' : 'Out of Stock',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: inStock ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sold by Card
              Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: MMColors.sage, width: 0.8),
                ),
                elevation: 0,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: MMColors.sage,
                    child: Icon(Icons.storefront, color: MMColors.primaryGreen),
                  ),
                  title: Row(
                    children: [
                      Text(storeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 15, color: MMColors.primaryGreen),
                    ],
                  ),
                  subtitle: const Text('Verified Local Home Entrepreneur', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.primaryGreen),
                  onTap: storeId.isNotEmpty ? () => context.push('/business/$storeId') : null,
                ),
              ),
              const SizedBox(height: 16),

              // Quantity Selector
              Row(
                children: [
                  const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: MMColors.sage),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('$_quantity',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: _quantity < stock ? () => setState(() => _quantity++) : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Purchase Buttons: Add to Cart & Buy Now
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: MMColors.primaryGreen, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.shopping_bag_outlined, color: MMColors.primaryGreen),
                        label: const Text('Add to Cart',
                            style: TextStyle(
                                color: MMColors.primaryGreen, fontWeight: FontWeight.w700, fontSize: 15)),
                        onPressed: (inStock && !_isAdding) ? () => _addToCart(product: p) : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: MMColors.primaryGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.bolt, color: Colors.white),
                        label: const Text('⚡ Buy Now',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        onPressed: (inStock && !_isAdding)
                            ? () => _addToCart(navigateToCheckout: true, product: p)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Delivery Information Card
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
                        children: [
                          const Icon(Icons.local_shipping_outlined, color: MMColors.primaryGreen, size: 20),
                          const SizedBox(width: 8),
                          Text('Delivery Information',
                              style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (homeDelivery)
                            Chip(
                              label: Text('Home Delivery: ₹$deliveryCharge'),
                              backgroundColor: MMColors.sage,
                              visualDensity: VisualDensity.compact,
                            ),
                          const SizedBox(width: 8),
                          if (pickup)
                            const Chip(
                              label: Text('Pickup Available'),
                              backgroundColor: MMColors.cream,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('Estimated Delivery: Today before 5:30 PM',
                          style: TextStyle(fontSize: 13, color: MMColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              Text('Description', style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                p['description']?.toString() ?? 'Handcrafted fresh with traditional care and quality.',
                style: const TextStyle(fontSize: 14, height: 1.5, color: MMColors.textPrimary),
              ),
              const SizedBox(height: 16),

              // Customization field (e.g. Cake message, notes)
              TextField(
                controller: _customizationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Customization (Optional)',
                  hintText: 'e.g., Happy Birthday message, spice level...',
                ),
              ),
              const SizedBox(height: 16),

              // After Sales Support Box
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
                      Text('After Sales Support',
                          style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            supportType != 'not_available' ? Icons.check_circle : Icons.cancel,
                            size: 16,
                            color: supportType != 'not_available' ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(supportType == 'not_available'
                              ? 'After-sales support not applicable'
                              : supportType == 'replacement_only'
                                  ? 'Replacement Available'
                                  : 'Return & Replacement Available'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Support Window: $supportWindow',
                          style: const TextStyle(fontSize: 12, color: MMColors.textSecondary)),
                      if (returnRequired)
                        const Text('Return Required: Yes',
                            style: TextStyle(fontSize: 12, color: MMColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
