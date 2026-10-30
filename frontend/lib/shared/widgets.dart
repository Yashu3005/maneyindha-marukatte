import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

String rupees(dynamic amount) => '₹${(amount ?? 0).toString()}';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
      child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 3))));
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 22),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  final String message;
  const EmptyView({super.key, required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text(message, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

/// The picture that represents a shop: the server's `coverUrl`, else its cover/logo. Null when the shop has none.
String? shopCover(Map? shop) {
  for (final k in const ['coverUrl', 'bannerUrl', 'logoUrl']) {
    final v = shop?[k]?.toString();
    if (v != null && v.startsWith('https://')) return v;
  }
  return null;
}

class NetImage extends StatelessWidget {
  final String? url;
  final double? height;
  final double? width;
  const NetImage(this.url, {super.key, this.height, this.width});

  // The same soft placeholder for "no photo" and "photo could not load", so cards never show a broken image.
  Widget _placeholder() => Container(
        height: height, width: width,
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [MMColors.sage, MMColors.blush],
        )),
        child: const Icon(Icons.storefront, color: MMColors.olive),
      );

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return _placeholder();
    return Image.network(
      url!, height: height, width: width, fit: BoxFit.cover,
      // Keeps the card's size steady while the picture downloads (no layout jump).
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              height: height, width: width, color: MMColors.sage.withOpacity(0.35),
              child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }
}

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const ProductCard({super.key, required this.product});
  @override
  Widget build(BuildContext context) {
    final images = (product['images'] as List?) ?? [];
    return Container(
      decoration: BoxDecoration(
        color: MMColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(0.09),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/product/${product['_id']}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: SizedBox(
            width: double.infinity,
            child: NetImage(images.isNotEmpty ? images.first.toString() : null),
          )),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product['name']?.toString() ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(rupees(product['price']),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700)),
                RatingBadge(rating: product['rating']),
              ]),
            ]),
          ),
        ]),
      ),
    );
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
      return Text('New', style: Theme.of(context).textTheme.bodySmall);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${r['avg']}',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        const Icon(Icons.star, size: 12, color: Colors.white),
      ]),
    );
  }
}
