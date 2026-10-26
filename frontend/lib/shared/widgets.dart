import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/auth_state.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';

String rupees(dynamic amount) {
  if (amount == null) return '₹0';
  final numVal = amount is num ? amount : num.tryParse(amount.toString()) ?? 0;
  return '₹${numVal.toStringAsFixed(numVal.truncateToDouble() == numVal ? 0 : 2)}';
}

/// Responsive constraint wrapper ensuring comfortable margins on wide screens.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 1180,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Shimmering pulsing box for skeleton loading.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.35 + (_controller.value * 0.45);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: MMColors.sand.withValues(alpha: opacity),
            borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
          ),
        );
      },
    );
  }
}

/// Skeleton for product grid items during initial load.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SkeletonBox(
                width: double.infinity,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            SizedBox(height: 10),
            SkeletonBox(width: 120, height: 16),
            SizedBox(height: 6),
            SkeletonBox(width: 80, height: 12),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBox(width: 60, height: 18),
                SkeletonBox(width: 44, height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: MMColors.deepOlive,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 14),
                Text(message!, style: sans(14, color: MMColors.textSecondary)),
              ],
            ],
          ),
        ),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEAEA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 32,
                  color: Color(0xFFBA1A1A),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Something went wrong',
                style: serif(18, color: MMColors.deepOlive),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: sans(14, color: MMColors.textSecondary),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                ),
              ],
            ],
          ),
        ),
      );
}

class EmptyView extends StatelessWidget {
  final String message;
  final String? subtitle;
  final IconData icon;
  final String? buttonLabel;
  final VoidCallback? onButtonPressed;

  const EmptyView({
    super.key,
    required this.message,
    this.subtitle,
    this.icon = Icons.storefront_outlined,
    this.buttonLabel,
    this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: MMColors.sageLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: MMColors.deepOlive),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: serif(20, color: MMColors.deepOlive),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: sans(14, color: MMColors.textSecondary),
                ),
              ],
              if (buttonLabel != null && onButtonPressed != null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onButtonPressed,
                  child: Text(buttonLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

class NetImage extends StatelessWidget {
  final String? url;
  final double? height;
  final double? width;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const NetImage(
    this.url, {
    super.key,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (url == null || url!.isEmpty) {
      imageWidget = Container(
        height: height,
        width: width,
        color: MMColors.cream,
        child: const Center(
          child: Icon(Icons.spa_outlined, color: MMColors.oliveLight, size: 28),
        ),
      );
    } else {
      imageWidget = Image.network(
        url!,
        height: height,
        width: width,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: height,
            width: width,
            color: MMColors.creamLight,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MMColors.oliveLight,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          height: height,
          width: width,
          color: MMColors.cream,
          child: const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: MMColors.textMuted,
              size: 24,
            ),
          ),
        ),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }
    return imageWidget;
  }
}

class RatingBadge extends StatelessWidget {
  final dynamic rating;
  const RatingBadge({super.key, this.rating});

  @override
  Widget build(BuildContext context) {
    final r = rating is Map ? rating as Map : const {};
    final count = (r['count'] ?? 0) as num;
    if (count == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: MMColors.sageLight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'NEW',
          style: sans(11, weight: FontWeight.w700, color: MMColors.deepOlive),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: MMColors.marigoldLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MMColors.marigold.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: MMColors.marigold),
          const SizedBox(width: 3),
          Text(
            '${r['avg']}',
            style: sans(12, weight: FontWeight.w700, color: const Color(0xFF8A5506)),
          ),
          if (count > 0) ...[
            const SizedBox(width: 2),
            Text(
              '($count)',
              style: sans(11, color: const Color(0xFF8A5506)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Redesigned Product Card with Indian marketplace aesthetic, subtle shadow, and quick add-to-cart action.
class ProductCard extends ConsumerWidget {
  final Map<String, dynamic> product;
  const ProductCard({super.key, required this.product});

  Future<void> _quickAddToCart(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.push('/login');
      return;
    }

    final id = product['_id']?.toString() ?? '';
    try {
      await ApiClient.dio.post('/cart/items', data: {'productId': id, 'quantity': 1});
      ref.invalidate(cartProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Added "${product['name']}" to your cart',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'View Cart',
              textColor: MMColors.terracottaLight,
              onPressed: () => context.push('/cart'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = (product['images'] as List?) ?? [];
    final stock = (product['stock'] ?? 0) as num;
    final business = product['business'];
    final businessName = business is Map ? (business['name']?.toString() ?? '') : '';

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => context.push('/product/${product['_id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image + badges overlay
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(images.isNotEmpty ? images.first.toString() : null),
                  // Out of stock or low stock badge
                  if (stock <= 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFBA1A1A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Sold Out',
                          style: sans(11, weight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    )
                  else if (stock < 5)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: MMColors.terracotta,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Only $stock Left',
                          style: sans(11, weight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Product Details
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (businessName.isNotEmpty) ...[
                    Text(
                      businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11, color: MMColors.textMuted, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    product['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: serif(15, weight: FontWeight.w600, color: MMColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        rupees(product['price']),
                        style: sans(16, weight: FontWeight.w800, color: MMColors.deepOlive),
                      ),
                      RatingBadge(rating: product['rating']),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: MMColors.deepOlive, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: stock > 0 ? () => _quickAddToCart(context, ref) : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            stock > 0 ? Icons.add_shopping_cart_rounded : Icons.block,
                            size: 15,
                            color: stock > 0 ? MMColors.deepOlive : MMColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            stock > 0 ? 'Add' : 'Out of stock',
                            style: sans(12,
                                weight: FontWeight.w600,
                                color: stock > 0 ? MMColors.deepOlive : MMColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
