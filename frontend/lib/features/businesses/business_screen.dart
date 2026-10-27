import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repositories.dart';
import '../../shared/rating_widgets.dart';
import 'promo_video.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class BusinessScreen extends ConsumerWidget {
  final String id;
  const BusinessScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessProvider(id));
    final products = ref.watch(productsProvider(id));

    return Scaffold(
      appBar: AppBar(title: const Text('Shop')),
      body: business.when(
        loading: () => const LoadingView(),
        error: (e, _) => const ErrorView(message: 'Could not load this shop.'),
        data: (b) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (b['promoVideo'] is Map && (b['promoVideo'] as Map)['url'] != null)
              PromoVideoCard(
                key: ValueKey((b['promoVideo'] as Map)['url']),
                video: Map<String, dynamic>.from(b['promoVideo'] as Map),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: softShadow(0.16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 190, width: double.infinity,
                  child: Stack(fit: StackFit.expand, children: [
                    NetImage(b['bannerUrl']?.toString()),
                    // darkens the bottom so the shop name stays readable on any photo
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC1F2812)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16, right: 16, bottom: 14,
                      child: Row(children: [
                        Expanded(
                          child: Text(b['name']?.toString() ?? '',
                              style: serif(24, color: Colors.white)),
                        ),
                        const Icon(Icons.verified, color: Colors.white),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((b['description']?.toString() ?? '').isNotEmpty) Text(b['description'].toString()),
                if ([
                  (b['address'] as Map?)?['line1'],
                  (b['address'] as Map?)?['city'],
                ].any((x) => x != null)) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: MMColors.moss),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [
                          (b['address'] as Map?)?['line1'],
                          (b['address'] as Map?)?['city'],
                        ].where((x) => x != null).join(', '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            RatingSummaryCard(businessId: id),
            const SizedBox(height: 24),
            Text('Products', style: serif(20)),
            const SizedBox(height: 12),
            products.when(
              loading: () => const LoadingView(),
              error: (e, _) => const ErrorView(message: 'Could not load products.'),
              data: (items) => items.isEmpty
                  ? const EmptyView(message: 'No products listed yet.')
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 240,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => ProductCard(product: items[i]),
                    ),
            ),
            const SizedBox(height: 24),
            Text('What customers say', style: serif(20)),
            const SizedBox(height: 12),
            ReviewsList(businessId: id),
          ],
        ),
      ),
    );
  }
}
