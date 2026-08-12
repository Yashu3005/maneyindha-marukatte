import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';

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
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(height: 160, width: double.infinity,
                  child: NetImage(b['bannerUrl']?.toString())),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text(b['name']?.toString() ?? '',
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              const Icon(Icons.verified, color: Colors.teal),
            ]),
            const SizedBox(height: 8),
            Text(b['description']?.toString() ?? ''),
            const SizedBox(height: 8),
            Text(
              [
                (b['address'] as Map?)?['line1'],
                (b['address'] as Map?)?['city'],
              ].where((x) => x != null).join(', '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Text('Products', style: Theme.of(context).textTheme.titleLarge),
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
          ],
        ),
      ),
    );
  }
}
