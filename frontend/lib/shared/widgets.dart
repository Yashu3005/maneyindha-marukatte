import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

class NetImage extends StatelessWidget {
  final String? url;
  final double? height;
  final double? width;
  const NetImage(this.url, {super.key, this.height, this.width});
  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        height: height, width: width,
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const Icon(Icons.storefront),
      );
    }
    return Image.network(url!, height: height, width: width, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
              height: height, width: width,
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Icon(Icons.image_not_supported),
            ));
  }
}

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const ProductCard({super.key, required this.product});
  @override
  Widget build(BuildContext context) {
    final images = (product['images'] as List?) ?? [];
    return Card(
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
