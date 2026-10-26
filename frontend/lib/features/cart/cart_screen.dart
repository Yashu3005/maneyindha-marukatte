import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _coupon = TextEditingController();
  bool _applyingCoupon = false;

  Future<void> _updateQty(String productId, int quantity) async {
    try {
      await ApiClient.dio.patch('/cart/items',
          data: {'productId': productId, 'quantity': quantity});
      ref.invalidate(cartProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e))),
        );
      }
    }
  }

  Future<void> _applyCoupon() async {
    final code = _coupon.text.trim();
    if (code.isEmpty) return;

    setState(() => _applyingCoupon = true);
    try {
      await ApiClient.dio.post('/cart/coupon', data: {'code': code});
      ref.invalidate(cartProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Coupon "$code" applied! 🎉')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Cart')),
        body: EmptyView(
          message: 'Sign in to see your cart',
          subtitle: 'Your selected homemade creations will appear here.',
          icon: Icons.shopping_bag_outlined,
          buttonLabel: 'Sign In / Register',
          onButtonPressed: () => context.push('/login'),
        ),
      );
    }

    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Cart',
            onPressed: () => ref.invalidate(cartProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: cart.when(
        loading: () => const LoadingView(message: 'Loading your cart…'),
        error: (e, _) => ErrorView(
          message: apiError(e),
          onRetry: () => ref.invalidate(cartProvider),
        ),
        data: (c) {
          final items = (c['items'] as List?) ?? [];
          final totals = (c['totals'] as Map?) ?? {};
          final business = c['business'];
          final appliedCoupon = c['coupon']?.toString();

          if (items.isEmpty) {
            return EmptyView(
              message: 'Your cart is empty',
              subtitle: 'Discover delicious homemade food and artisan crafts near you.',
              icon: Icons.shopping_bag_outlined,
              buttonLabel: 'Explore Marketplace',
              onButtonPressed: () => context.go('/app'),
            );
          }

          return ResponsiveContainer(
            maxWidth: 820,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ListView(
              children: [
                // Single Seller Shop banner notice
                if (business is Map && business['name'] != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: MMColors.sageLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            size: 20, color: MMColors.deepOlive),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: sans(13, color: MMColors.textPrimary),
                              children: [
                                const TextSpan(text: 'Ordering fresh from '),
                                TextSpan(
                                  text: business['name'].toString(),
                                  style: sans(13,
                                      weight: FontWeight.w700,
                                      color: MMColors.deepOlive),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Item Cards
                ...items.map((raw) {
                  final item = Map<String, dynamic>.from(raw as Map);
                  final product = item['product'] is Map
                      ? Map<String, dynamic>.from(item['product'] as Map)
                      : <String, dynamic>{};
                  final qty = (item['quantity'] ?? 1) as int;
                  final images = (product['images'] as List?) ?? [];
                  final pId = product['_id']?.toString() ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 68,
                              height: 68,
                              child: NetImage(
                                  images.isNotEmpty ? images.first.toString() : null),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product['name']?.toString() ?? 'Homemade Item',
                                  style: serif(16, weight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rupees(product['price']),
                                  style: sans(15,
                                      weight: FontWeight.w800,
                                      color: MMColors.deepOlive),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: MMColors.cream,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: MMColors.borderLight),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove, size: 16),
                                  onPressed: () => _updateQty(pId, qty - 1),
                                ),
                                Text('$qty', style: sans(15, weight: FontWeight.w700)),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add, size: 16),
                                  onPressed: () => _updateQty(pId, qty + 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 16),

                // Coupon Code Box
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Apply Discount Coupon', style: serif(16, weight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _coupon,
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  hintText: appliedCoupon ?? 'Enter coupon code',
                                  prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 20),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              onPressed: _applyingCoupon ? null : _applyCoupon,
                              child: _applyingCoupon
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Apply'),
                            ),
                          ],
                        ),
                        if (appliedCoupon != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 16, color: MMColors.olive),
                              const SizedBox(width: 6),
                              Text(
                                'Coupon "$appliedCoupon" is active',
                                style: sans(13,
                                    weight: FontWeight.w600,
                                    color: MMColors.deepOlive),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Bill Summary Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bill Summary', style: serif(18, weight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        _summaryRow('Item Subtotal', rupees(totals['subtotal'])),
                        if ((totals['discount'] ?? 0) != 0) ...[
                          const SizedBox(height: 8),
                          _summaryRow(
                            'Coupon Discount',
                            '- ${rupees(totals['discount'])}',
                            color: MMColors.terracotta,
                          ),
                        ],
                        const SizedBox(height: 8),
                        _summaryRow('Delivery Fee', 'Calculated at checkout',
                            style: sans(13, color: MMColors.textMuted)),
                        const Divider(height: 24),
                        _summaryRow(
                          'Estimated Total',
                          rupees(totals['total'] ?? totals['subtotal']),
                          bold: true,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Proceed Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/checkout'),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: const Text('Proceed to Checkout'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    double size = 14,
    Color? color,
    TextStyle? style,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: sans(size,
              weight: bold ? FontWeight.w700 : FontWeight.w400,
              color: color ?? MMColors.textSecondary),
        ),
        Text(
          value,
          style: style ??
              sans(size,
                  weight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color ?? (bold ? MMColors.deepOlive : MMColors.textPrimary)),
        ),
      ],
    );
  }
}
