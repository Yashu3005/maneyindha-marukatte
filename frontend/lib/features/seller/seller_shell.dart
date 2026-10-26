import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

/// Entrepreneur app: Dashboard · Products · Orders · Earnings · Profile.
class SellerShell extends ConsumerStatefulWidget {
  const SellerShell({super.key});
  @override
  ConsumerState<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends ConsumerState<SellerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: const [
        _DashboardTab(),
        _ProductsTab(),
        _SellerOrdersTab(),
        _EarningsTab(),
        _SellerProfileTab(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Products'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

String? _shopId(List<Map<String, dynamic>> shops) =>
    shops.isEmpty ? null : shops.first['_id'].toString();

num _earnings(List<Map<String, dynamic>> orders, {Duration? window}) {
  final cutoff = window == null ? null : DateTime.now().subtract(window);
  num total = 0;
  for (final o in orders) {
    if (o['status'] != 'delivered') continue;
    if (cutoff != null) {
      final created = DateTime.tryParse(o['createdAt']?.toString() ?? '');
      if (created == null || created.isBefore(cutoff)) continue;
    }
    total += ((o['amounts'] as Map?)?['total'] ?? 0) as num;
  }
  return total;
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Card(
        color: MMColors.cream,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, textAlign: TextAlign.center,
                style: serif(15, weight: FontWeight.w400)),
            const SizedBox(height: 6),
            Text(value, style: serif(22)),
          ]),
        ),
      );
}

// ---------------- Dashboard ----------------
class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final shops = ref.watch(myBusinessesProvider);
    final orders = ref.watch(ordersProvider);

    return Container(
      color: MMColors.olive,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: MMColors.cream,
              backgroundImage: (auth.user?['avatarUrl'] != null)
                  ? NetworkImage(auth.user!['avatarUrl'].toString())
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Welcome,\n${auth.name}',
                  style: serif(20, color: MMColors.cream)),
            ),
            const Icon(Icons.notifications_none, color: MMColors.cream),
          ]),
          const SizedBox(height: 20),
          shops.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(message: apiError(e)),
            data: (myShops) {
              final rating = myShops.isEmpty
                  ? {}
                  : (myShops.first['rating'] as Map? ?? {});
              final products = _shopId(myShops) == null
                  ? const AsyncValue.data(<Map<String, dynamic>>[])
                  : ref.watch(productsProvider(_shopId(myShops)));
              final orderList = orders.asData?.value ?? [];
              final received = orderList
                  .where((o) => (o['business'] as Map?)?['_id'] != null || true)
                  .toList();
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.7,
                children: [
                  _StatCard(label: 'Total Orders', value: '${received.length}'),
                  _StatCard(label: 'Total Earnings', value: rupees(_earnings(received))),
                  _StatCard(label: 'Total Products',
                      value: '${products.asData?.value.length ?? 0}'),
                  _StatCard(label: 'Average Rating',
                      value: (rating['count'] ?? 0) == 0 ? 'New' : '${rating['avg']} ★'),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text('Recent Orders', style: serif(18, color: MMColors.cream)),
          const SizedBox(height: 8),
          orders.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(message: apiError(e)),
            data: (items) => items.isEmpty
                ? Card(color: MMColors.cream,
                    child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No orders yet — your first one is coming!')))
                : Column(
                    children: items.take(5).map((o) {
                      return Card(
                        color: MMColors.cream,
                        child: ListTile(
                          title: Text('${o['orderNumber']}', style: serif(15)),
                          subtitle: Text('${((o['items'] as List?) ?? []).length} items'),
                          trailing: Chip(label: Text(o['status'].toString())),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Products ----------------
class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab();
  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab> {
  Future<void> _addProduct(String businessId) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final stock = TextEditingController(text: '10');
    final description = TextEditingController();
    String? imageUrl;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        return AlertDialog(
          title: const Text('Add product'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name,
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 10),
                TextField(controller: price, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price (₹)')),
                const SizedBox(height: 10),
                TextField(controller: stock, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stock')),
                const SizedBox(height: 10),
                TextField(controller: description, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(imageUrl == null ? 'Product photo:' : 'Photo selected ✓'),
                ),
                const SizedBox(height: 6),
                Consumer(builder: (c, r, _) {
                  final photos = r.watch(imagesProvider(
                      name.text.trim().isEmpty ? 'handmade product' : name.text.trim()));
                  return photos.when(
                    loading: () => const SizedBox(
                        height: 70, child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => const SizedBox(),
                    data: (urls) => SizedBox(
                      height: 70,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: urls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => setD(() => imageUrl = urls[i]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(children: [
                              Image.network(urls[i], width: 70, height: 70, fit: BoxFit.cover),
                              if (imageUrl == urls[i])
                                const Positioned(
                                    right: 2, top: 2,
                                    child: Icon(Icons.check_circle,
                                        color: Colors.white, size: 18)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        );
      }),
    );
    if (saved != true) return;

    try {
      await ApiClient.dio.post('/products', data: {
        'business': businessId,
        'name': name.text.trim(),
        'price': num.tryParse(price.text) ?? 0,
        'stock': num.tryParse(stock.text) ?? 0,
        'description': description.text.trim(),
        if (imageUrl != null) 'images': [imageUrl],
      });
      ref.invalidate(productsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Product added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _deleteProduct(String id) async {
    try {
      await ApiClient.dio.delete('/products/$id');
      ref.invalidate(productsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shops = ref.watch(myBusinessesProvider);
    return SafeArea(
      child: shops.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: apiError(e),
            onRetry: () => ref.invalidate(myBusinessesProvider)),
        data: (myShops) {
          final shopId = _shopId(myShops);
          if (shopId == null) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('No business found on this account.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go('/seller/onboarding/business'),
                  child: const Text('Set up your business'),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(myBusinessesProvider),
                  child: const Text('I already have one — refresh'),
                ),
              ]),
            );
          }
          final products = ref.watch(productsProvider(shopId));
          return Column(children: [
            ListTile(
              title: Text('My Products', style: serif(20)),
              trailing: FilledButton.icon(
                onPressed: () => _addProduct(shopId),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ),
            Expanded(
              child: products.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(message: apiError(e)),
                data: (items) => items.isEmpty
                    ? const EmptyView(message: 'No products yet — add your first one!')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = items[i];
                          final images = (p['images'] as List?) ?? [];
                          return Card(
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(width: 56, height: 56,
                                    child: NetImage(images.isNotEmpty
                                        ? images.first.toString() : null)),
                              ),
                              title: Text(p['name']?.toString() ?? ''),
                              subtitle: Text('${rupees(p['price'])} · Stock: ${p['stock']}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteProduct(p['_id'].toString()),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ---------------- Orders (with status actions) ----------------
class _SellerOrdersTab extends ConsumerWidget {
  const _SellerOrdersTab();

  Future<void> _transition(BuildContext context, WidgetRef ref, String id, String status) async {
    try {
      await ApiClient.dio.patch('/orders/$id/status', data: {'status': status});
      ref.invalidate(ordersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    const nextStep = {
      'pending': 'confirmed',
      'confirmed': 'preparing',
      'preparing': 'ready',
      'ready': 'picked_up',
      'picked_up': 'out_for_delivery',
      'out_for_delivery': 'delivered',
    };
    return SafeArea(
      child: Column(children: [
        ListTile(title: Text('Orders Received', style: serif(20))),
        Expanded(
          child: orders.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
                message: apiError(e), onRetry: () => ref.invalidate(ordersProvider)),
            data: (items) => items.isEmpty
                ? const EmptyView(message: 'No orders yet.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final o = items[i];
                      final status = o['status'].toString();
                      final next = nextStep[status];
                      final amounts = (o['amounts'] as Map?) ?? {};
                      return Card(
                        child: ListTile(
                          title: Text('${o['orderNumber']} · ${rupees(amounts['total'])}'),
                          subtitle: Text(((o['items'] as List?) ?? [])
                              .map((it) => '${(it as Map)['name']} × ${it['quantity']}')
                              .join(', ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Chip(label: Text(status.replaceAll('_', ' '))),
                            if (next != null) ...[
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => _transition(
                                    context, ref, o['_id'].toString(), next),
                                child: Text(next == 'confirmed'
                                    ? 'Confirm'
                                    : next.replaceAll('_', ' ')),
                              ),
                            ],
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

// ---------------- Earnings ----------------
class _EarningsTab extends ConsumerWidget {
  const _EarningsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    return SafeArea(
      child: orders.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e)),
        data: (items) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('Earnings', style: serif(22)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              _StatCard(label: 'Today',
                  value: rupees(_earnings(items, window: const Duration(days: 1)))),
              _StatCard(label: 'This Week',
                  value: rupees(_earnings(items, window: const Duration(days: 7)))),
              _StatCard(label: 'This Month',
                  value: rupees(_earnings(items, window: const Duration(days: 30)))),
              _StatCard(label: 'All Time', value: rupees(_earnings(items))),
            ],
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Earnings count delivered orders. '
                  'Payouts to your bank arrive in the payments phase.'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Profile ----------------
class _SellerProfileTab extends ConsumerWidget {
  const _SellerProfileTab();

  Future<void> _bankDetails(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    final bank = (auth.user?['bankAccount'] as Map?) ?? {};
    final holder = TextEditingController(text: bank['holder']?.toString() ?? '');
    final account = TextEditingController(text: bank['account']?.toString() ?? '');
    final ifsc = TextEditingController(text: bank['ifsc']?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bank details'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: holder,
              decoration: const InputDecoration(labelText: 'Account holder')),
          const SizedBox(height: 10),
          TextField(controller: account,
              decoration: const InputDecoration(labelText: 'Account number')),
          const SizedBox(height: 10),
          TextField(controller: ifsc,
              decoration: const InputDecoration(labelText: 'IFSC')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await ref.read(authProvider.notifier).updateProfile({
        'bankAccount': {
          'holder': holder.text.trim(),
          'account': account.text.trim(),
          'ifsc': ifsc.text.trim(),
        },
      });
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final password = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: TextField(controller: password, obscureText: true,
            decoration: const InputDecoration(labelText: 'New password (min 6 chars)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && password.text.length >= 6) {
      final username = ref.read(authProvider).user?['username']?.toString() ?? '';
      await ref.read(authProvider.notifier).setCredentials(username, password.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password updated')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final shops = ref.watch(myBusinessesProvider);
    final shopId = shops.asData?.value.isNotEmpty == true
        ? shops.asData!.value.first['_id'].toString()
        : null;

    return Container(
      color: MMColors.olive,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: CircleAvatar(
            radius: 44,
            backgroundColor: MMColors.cream,
            backgroundImage: (auth.user?['avatarUrl'] != null)
                ? NetworkImage(auth.user!['avatarUrl'].toString())
                : null,
          )),
          const SizedBox(height: 12),
          Center(child: Text(auth.name, style: serif(22, color: MMColors.cream))),
          Center(child: Text(auth.email,
              style: serif(14, weight: FontWeight.w400, color: MMColors.cream))),
          const SizedBox(height: 20),
          Card(color: MMColors.cream, child: Column(children: [
            ListTile(
              title: const Text('Business Profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog(
                context: context,
                builder: (ctx) {
                  final shop = shops.asData?.value.isNotEmpty == true
                      ? shops.asData!.value.first
                      : null;
                  return AlertDialog(
                    title: const Text('Business Profile'),
                    content: shop == null
                        ? const Text('No business yet.')
                        : Text('${shop['name']}\n'
                            'Status: ${(shop['verification'] as Map?)?['status']}\n'
                            'Experience: ${shop['yearsOfExperience'] ?? '-'}\n'
                            '${shop['description'] ?? ''}'),
                  );
                },
              ),
            ),
            ListTile(
              title: const Text('Bank Details'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _bankDetails(context, ref),
            ),
            ListTile(
              title: const Text('Address'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog(
                context: context,
                builder: (ctx) {
                  final shop = shops.asData?.value.isNotEmpty == true
                      ? shops.asData!.value.first
                      : null;
                  final address = (shop?['address'] as Map?) ?? {};
                  return AlertDialog(
                    title: const Text('Business address'),
                    content: Text('${address['line1'] ?? '-'}, ${address['city'] ?? ''}'),
                  );
                },
              ),
            ),
            ListTile(
              title: const Text('Change Password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changePassword(context, ref),
            ),
            ListTile(
              title: const Text('Become a customer'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await ref.read(authProvider.notifier).switchRole('customer');
                ref.invalidate(ordersProvider);
                ref.invalidate(cartProvider);
                if (context.mounted) context.go('/app');
              },
            ),
            ListTile(
              title: const Text('Reviews'),
              trailing: const Icon(Icons.chevron_right),
              onTap: shopId == null ? null : () => showDialog(
                context: context,
                builder: (ctx) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460, maxHeight: 480),
                    child: Consumer(builder: (c, r, _) {
                      final reviews = r.watch(businessReviewsProvider(shopId));
                      return reviews.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Padding(
                            padding: const EdgeInsets.all(16), child: Text(apiError(e))),
                        data: (items) => items.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('No reviews yet.'))
                            : ListView(
                                padding: const EdgeInsets.all(16),
                                children: items
                                    .map((rv) => ListTile(
                                          leading: const Icon(Icons.star,
                                              color: MMColors.marigold),
                                          title: Text('${rv['rating']} ★ · '
                                              '${(rv['customer'] as Map?)?['name'] ?? ''}'),
                                          subtitle: Text(rv['comment']?.toString() ?? ''),
                                        ))
                                    .toList(),
                              ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            ListTile(
              title: const Text('Logout'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ref.read(authProvider.notifier).logout();
                context.go('/');
              },
            ),
          ])),
        ]),
      ),
    );
  }
}
