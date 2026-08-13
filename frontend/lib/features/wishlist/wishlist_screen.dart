import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

final wishlistProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/wishlist');
  return Map<String, dynamic>.from(res.data['data'] as Map);
});

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlist = ref.watch(wishlistProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: wishlist.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: apiError(e), onRetry: () => ref.invalidate(wishlistProvider)),
        data: (w) {
          final products = ((w['products'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final shops = ((w['businesses'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)).toList();
          if (products.isEmpty && shops.isEmpty) {
            return const EmptyView(
                message: 'Nothing saved yet.\nTap the ♡ on products and shops you love!');
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (shops.isNotEmpty) ...[
                  Text('Shops you follow', style: serif(18)),
                  const SizedBox(height: 8),
                  ...shops.map((b) => Card(
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(width: 48, height: 48,
                                child: NetImage(b['logoUrl']?.toString())),
                          ),
                          title: Text(b['name']?.toString() ?? ''),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/business/${b['_id']}'),
                        ),
                      )),
                  const SizedBox(height: 16),
                ],
                if (products.isNotEmpty) ...[
                  Text('Saved products', style: serif(18)),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220, mainAxisSpacing: 12,
                      crossAxisSpacing: 12, childAspectRatio: 0.8),
                    itemCount: products.length,
                    itemBuilder: (_, i) => ProductCard(product: products[i]),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}
