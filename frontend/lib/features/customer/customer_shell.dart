import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/i18n.dart';
import '../../services/cloudinary.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import '../cart/cart_screen.dart';
import '../orders/orders_screen.dart';

/// Zomato-style customer app: bottom nav Home · Orders · Cart · Profile.
class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key});
  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: const [
        _CustomerHome(),
        OrdersScreen(),
        CartScreen(),
        _CommunityTab(),
        _CustomerProfile(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t(ref, 'home')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: t(ref, 'orders')),
          NavigationDestination(icon: const Icon(Icons.shopping_bag_outlined), selectedIcon: const Icon(Icons.shopping_bag), label: t(ref, 'cart')),
          NavigationDestination(icon: const Icon(Icons.diversity_3_outlined), selectedIcon: const Icon(Icons.diversity_3), label: t(ref, 'community')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t(ref, 'profile')),
        ],
      ),
    );
  }
}

class _CustomerHome extends ConsumerStatefulWidget {
  const _CustomerHome();
  @override
  ConsumerState<_CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends ConsumerState<_CustomerHome> {
  String _query = '';
  String? _category;
  bool _nearMe = false;
  List<Map<String, dynamic>>? _nearbyShops;
  bool _locating = false;

  Future<void> _toggleNearMe() async {
    if (_nearMe) {
      setState(() { _nearMe = false; _nearbyShops = null; });
      return;
    }
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }
      final pos = await Geolocator.getCurrentPosition();
      final res = await ApiClient.dio.get('/businesses/nearby', queryParameters: {
        'lat': pos.latitude, 'lng': pos.longitude, 'radiusKm': 50,
      });
      final shops = (res.data['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() { _nearMe = true; _nearbyShops = shops; });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not get location: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final businesses = ref.watch(businessesProvider);
    final products = ref.watch(productsProvider(null));

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(businessesProvider);
          ref.invalidate(productsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t(ref, 'namaste')}, ${auth.name.split(' ').first} 🌸', style: serif(24)),
                  Text(t(ref, 'discover')),
                ]),
              ),
              _NotificationBell(),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: MMColors.sage,
                backgroundImage: (auth.user?['avatarUrl'] != null)
                    ? NetworkImage(auth.user!['avatarUrl'].toString())
                    : null,
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t(ref, 'search_hint'),
              ),
            ),
            const SizedBox(height: 16),
            Text(t(ref, 'categories'), style: serif(18)),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: businesses.when(
                loading: () => const SizedBox(),
                error: (e, _) => const SizedBox(),
                data: (shops) {
                  // category name -> banner of the first shop in it
                  final catImages = <String, String?>{};
                  for (final b in shops) {
                    final c = b['category'];
                    if (c is Map && c['name'] != null) {
                      catImages.putIfAbsent(
                          c['name'].toString(), () => b['bannerUrl']?.toString());
                    }
                  }
                  final list = catImages.keys.toList();
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final name = list[i];
                      final selected = _category == name;
                      return GestureDetector(
                        onTap: () => setState(
                            () => _category = selected ? null : name),
                        child: Column(children: [
                          Container(
                            width: 78, height: 78,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? MMColors.deepOlive
                                    : MMColors.sage,
                                width: selected ? 3 : 1.5,
                              ),
                            ),
                            child: ClipOval(
                                child: NetImage(catImages[name],
                                    width: 78, height: 78)),
                          ),
                          const SizedBox(height: 6),
                          Text(name,
                              style: serif(12,
                                  weight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400)),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text(_nearMe ? t(ref, 'near_you') : t(ref, 'all_shops'), style: serif(18))),
              FilterChip(
                avatar: _locating
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 16),
                label: Text(t(ref, 'near_me')),
                selected: _nearMe,
                onSelected: (_) => _toggleNearMe(),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 170,
              child: businesses.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                    message: 'Could not load shops.',
                    onRetry: () => ref.invalidate(businessesProvider)),
                data: (allShops) {
                  final shops = _nearMe ? (_nearbyShops ?? []) : allShops;
                  final filtered = shops.where((b) {
                    if (_category == null) return true;
                    final c = b['category'];
                    return c is Map && c['name'] == _category;
                  }).toList();
                  if (filtered.isEmpty) {
                    return EmptyView(
                        message: _nearMe
                            ? t(ref, 'coming_soon')
                            : 'No shops in this category yet.');
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _ShopCard(business: filtered[i]),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(t(ref, 'popular'), style: serif(18)),
            const SizedBox(height: 8),
            products.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                  message: 'Could not load products.',
                  onRetry: () => ref.invalidate(productsProvider)),
              data: (items) {
                var list = List<Map<String, dynamic>>.from(items);
                if (_query.isNotEmpty) {
                  list = list
                      .where((p) => p['name']
                          .toString()
                          .toLowerCase()
                          .contains(_query))
                      .toList();
                }
                list.sort((a, b) {
                  final ra = ((a['rating'] as Map?)?['count'] ?? 0) as num;
                  final rb = ((b['rating'] as Map?)?['count'] ?? 0) as num;
                  return rb.compareTo(ra);
                });
                if (list.isEmpty) {
                  return const EmptyView(message: 'No products match your search.');
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => ProductCard(product: list[i]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  final Map<String, dynamic> business;
  const _ShopCard({required this.business});

  @override
  Widget build(BuildContext context) {
    final rating = (business['rating'] as Map?) ?? {};
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/business/${business['_id']}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: 90, width: double.infinity,
                child: NetImage(business['bannerUrl']?.toString())),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(business['name']?.toString() ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: serif(15)),
                  ),
                  const Icon(Icons.verified, size: 15, color: MMColors.deepOlive),
                ]),
                const SizedBox(height: 4),
                Text(
                  (rating['count'] ?? 0) == 0
                      ? 'New shop'
                      : '★ ${rating['avg']} (${rating['count']})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CustomerProfile extends ConsumerWidget {
  const _CustomerProfile();

  Future<void> _editPersonal(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    final name = TextEditingController(text: auth.name);
    final phone = TextEditingController(text: auth.user?['phone']?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Personal details'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await ref.read(authProvider.notifier)
          .updateProfile({'name': name.text.trim(), 'phone': phone.text.trim()});
    }
  }

  Future<void> _editAddress(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    final addresses = (auth.user?['addresses'] as List?) ?? [];
    final current = addresses.isNotEmpty
        ? (addresses.first as Map)['line1']?.toString() ?? ''
        : '';
    final line = TextEditingController(text: current);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(ref, 'address_book')),
        content: TextField(
            controller: line,
            decoration: const InputDecoration(labelText: 'Home address')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await ref.read(authProvider.notifier).updateProfile({
        'addresses': [{'label': 'Home', 'line1': line.text.trim()}],
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: CircleAvatar(
          radius: 44,
          backgroundColor: MMColors.sage,
          backgroundImage: (auth.user?['avatarUrl'] != null)
              ? NetworkImage(auth.user!['avatarUrl'].toString())
              : null,
        )),
        const SizedBox(height: 12),
        Center(child: Text(auth.name, style: serif(22))),
        Center(child: Text(auth.email)),
        const SizedBox(height: 20),
        Card(child: Column(children: [
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: Text(t(ref, 'coins')),
            trailing: Chip(label: Text('🪙 ${auth.user?['coins'] ?? 0}')),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(t(ref, 'wishlist')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/wishlist'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(t(ref, 'notifications')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(t(ref, 'language')),
            trailing: Text(languages[ref.watch(localeProvider)] ?? 'English'),
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: Text(t(ref, 'language')),
                children: languages.entries
                    .map((e) => SimpleDialogOption(
                          onPressed: () {
                            ref.read(localeProvider.notifier).set(e.key);
                            Navigator.pop(ctx);
                          },
                          child: Text(e.value),
                        ))
                    .toList(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(t(ref, 'personal')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editPersonal(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(t(ref, 'address_book')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editAddress(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(t(ref, 'become_seller')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final hasBusiness = await ref
                  .read(authProvider.notifier)
                  .switchRole('entrepreneur');
              ref.invalidate(myBusinessesProvider);
              ref.invalidate(ordersProvider);
              ref.invalidate(sellerOrdersProvider);
              if (context.mounted) {
                context.go(hasBusiness ? '/seller' : '/seller/onboarding/business');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: Text(t(ref, 'help')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => const AlertDialog(
                title: Text('Help & Support'),
                content: Text('Write to support@maneyindhamarukatte.in\nWe reply within 24 hours.'),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(t(ref, 'logout')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ref.read(authProvider.notifier).logout();
              context.go('/');
            },
          ),
        ])),
      ]),
    );
  }
}


class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(notificationsProvider);
    final unread = data.asData?.value['unread'] ?? 0;
    return IconButton(
      icon: Badge(
        isLabelVisible: (unread as num) > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await context.push('/notifications');
        ref.invalidate(notificationsProvider);
      },
    );
  }
}

class _CommunityTab extends ConsumerWidget {
  const _CommunityTab();

  Future<void> _like(WidgetRef ref, BuildContext context, String id) async {
    try {
      await ApiClient.dio.post('/community/$id/like');
      ref.invalidate(communityProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(communityProvider);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(communityProvider),
        child: posts.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
              message: apiError(e), onRetry: () => ref.invalidate(communityProvider)),
          data: (items) => items.isEmpty
              ? const EmptyView(
                  message: 'No community posts yet.\nEntrepreneurs share their stories here!')
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final p = items[i];
                        final shop = (p['business'] as Map?) ?? {};
                        final likes = (p['likes'] as List?) ?? [];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(width: 40, height: 40,
                                    child: NetImage(shop['logoUrl']?.toString())),
                              ),
                              title: Text(shop['name']?.toString() ?? '', style: serif(15)),
                            ),
                            if (p['image'] != null)
                              SizedBox(height: 260, width: double.infinity,
                                  child: NetImage(p['image'].toString())),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(p['caption']?.toString() ?? ''),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
                              child: Row(children: [
                                IconButton(
                                  icon: const Icon(Icons.favorite,
                                      color: MMColors.marigold, size: 20),
                                  onPressed: () => _like(ref, context, p['_id'].toString()),
                                ),
                                Text('${likes.length}'),
                              ]),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
