import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

final sellerTabProvider = StateProvider.autoDispose<int>((ref) => 0);

/// Entrepreneur app: Dashboard · Products · Orders · Earnings · Profile.
class SellerShell extends ConsumerWidget {
  const SellerShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(sellerTabProvider);
    return Scaffold(
      backgroundColor: MMColors.paper,
      body: IndexedStack(index: index, children: const [
        _DashboardTab(),
        _ProductsTab(),
        _SellerOrdersTab(),
        _EarningsTab(),
        _SellerProfileTab(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(sellerTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Earnings',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
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

Color _orderStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'delivered':
      return const Color(0xFF2E7D32);
    case 'out_for_delivery':
    case 'picked_up':
      return const Color(0xFF1565C0);
    case 'preparing':
    case 'ready':
      return MMColors.terracotta;
    case 'confirmed':
      return MMColors.olive;
    case 'pending':
      return const Color(0xFFB45309);
    case 'cancelled':
      return const Color(0xFFC62828);
    default:
      return Colors.grey.shade700;
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? MMColors.olive;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MMColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MMColors.sand),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: MMColors.muted,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: serif(22, color: MMColors.ink, weight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------- Dashboard ----------------
class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final shops = ref.watch(myBusinessesProvider);
    final orders = ref.watch(ordersProvider);

    return SafeArea(
      child: ResponsiveContainer(
        maxWidth: Breakpoints.desktop,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Welcome Header Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MMColors.olive, Color(0xFF384F35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F263A23),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: MMColors.cream,
                    backgroundImage: (auth.user?['avatarUrl'] != null)
                        ? NetworkImage(auth.user!['avatarUrl'].toString())
                        : null,
                    child: (auth.user?['avatarUrl'] == null)
                        ? Text(
                            auth.name.isNotEmpty ? auth.name[0].toUpperCase() : 'S',
                            style: serif(22, color: MMColors.olive, weight: FontWeight.w700),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Namaskara, ${auth.name}!',
                          style: serif(20, color: Colors.white, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Home Entrepreneur Dashboard',
                          style: TextStyle(color: Color(0xFFE2E8DE), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () {
                      ref.invalidate(myBusinessesProvider);
                      ref.invalidate(ordersProvider);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Metrics Grid
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
                final received = orderList;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmall = constraints.maxWidth < 600;
                    return GridView.count(
                      crossAxisCount: isSmall ? 2 : 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isSmall ? 1.5 : 1.7,
                      children: [
                        _StatCard(
                          label: 'Total Orders',
                          value: '${received.length}',
                          icon: Icons.receipt_long_outlined,
                          accentColor: MMColors.olive,
                        ),
                        _StatCard(
                          label: 'Total Revenue',
                          value: rupees(_earnings(received)),
                          icon: Icons.currency_rupee,
                          accentColor: MMColors.terracotta,
                        ),
                        _StatCard(
                          label: 'Active Products',
                          value: '${products.asData?.value.length ?? 0}',
                          icon: Icons.inventory_2_outlined,
                          accentColor: const Color(0xFF1565C0),
                        ),
                        _StatCard(
                          label: 'Customer Rating',
                          value: (rating['count'] ?? 0) == 0 ? 'New' : '${rating['avg']} ★',
                          icon: Icons.star_outline_rounded,
                          accentColor: MMColors.marigold,
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Orders', style: serif(18, color: MMColors.ink)),
                TextButton(
                  onPressed: () => ref.read(sellerTabProvider.notifier).state = 2,
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            orders.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(message: apiError(e)),
              data: (items) => items.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: MMColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: MMColors.sand),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.shopping_bag_outlined, size: 40, color: MMColors.muted),
                          SizedBox(height: 8),
                          Text('No orders yet — your first one is coming!'),
                        ],
                      ),
                    )
                  : Column(
                      children: items.take(5).map((o) {
                        final amounts = (o['amounts'] as Map?) ?? {};
                        final status = o['status'].toString();
                        final itemsList = (o['items'] as List?) ?? [];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: MMColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: MMColors.sand),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: MMColors.cream,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.receipt_outlined, color: MMColors.olive),
                            ),
                            title: Text(
                              '${o['orderNumber'] ?? 'Order'} · ${rupees(amounts['total'])}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${itemsList.length} items · ${itemsList.map((i) => (i as Map)['name']).join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: MMColors.muted),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _orderStatusColor(status).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _orderStatusColor(status),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Add New Product', style: serif(18)),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Product Name',
                        hintText: 'e.g. Masala Nipattu, Embroidered Saree',
                      ),
                      onChanged: (_) => setD(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: price,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Price (₹)',
                              prefixText: '₹ ',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: stock,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Available Stock',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Freshly made with traditional ingredients...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      imageUrl == null ? 'Select a representative photo:' : 'Photo selected ✓',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: imageUrl == null ? MMColors.muted : MMColors.olive,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Consumer(
                      builder: (c, r, _) {
                        final photos = r.watch(imagesProvider(
                          name.text.trim().isEmpty ? 'homemade product' : name.text.trim(),
                        ));
                        return photos.when(
                          loading: () => const SizedBox(
                            height: 70,
                            child: Center(child: CircularProgressIndicator()),
                          ),
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
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        urls[i],
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                      ),
                                      if (imageUrl == urls[i])
                                        Container(
                                          width: 70,
                                          height: 70,
                                          color: Colors.black38,
                                          child: const Icon(
                                            Icons.check_circle,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add Product'),
              ),
            ],
          );
        },
      ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e))),
        );
      }
    }
  }

  Future<void> _deleteProduct(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to remove "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiClient.dio.delete('/products/$id');
      ref.invalidate(productsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shops = ref.watch(myBusinessesProvider);
    return SafeArea(
      child: ResponsiveContainer(
        maxWidth: Breakpoints.desktop,
        child: shops.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            message: apiError(e),
            onRetry: () => ref.invalidate(myBusinessesProvider),
          ),
          data: (myShops) {
            final shopId = _shopId(myShops);
            if (shopId == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storefront, size: 48, color: MMColors.muted),
                      const SizedBox(height: 12),
                      const Text('No business found on this account.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => context.go('/seller/onboarding/business'),
                        child: const Text('Set up your business'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(myBusinessesProvider),
                        child: const Text('I already have one — refresh'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final products = ref.watch(productsProvider(shopId));
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('My Products', style: serif(20)),
                          const Text(
                            'Manage inventory, prices, and catalog',
                            style: TextStyle(fontSize: 12, color: MMColors.muted),
                          ),
                        ],
                      ),
                      FilledButton.icon(
                        onPressed: () => _addProduct(shopId),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Product'),
                      ),
                    ],
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
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final p = items[i];
                              final images = (p['images'] as List?) ?? [];
                              final stock = (p['stock'] ?? 0) as num;
                              final inStock = stock > 0;

                              return Container(
                                decoration: BoxDecoration(
                                  color: MMColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: MMColors.sand),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 54,
                                      height: 54,
                                      child: NetImage(
                                        images.isNotEmpty ? images.first.toString() : null,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    p['name']?.toString() ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Row(
                                    children: [
                                      Text(
                                        rupees(p['price']),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: MMColors.terracotta,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: inStock
                                              ? const Color(0xFFE8F5E9)
                                              : const Color(0xFFFFEBEE),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          inStock ? 'Stock: $stock' : 'Out of stock',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: inStock
                                                ? const Color(0xFF2E7D32)
                                                : const Color(0xFFC62828),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Color(0xFFC62828),
                                    ),
                                    onPressed: () => _deleteProduct(
                                      p['_id'].toString(),
                                      p['name']?.toString() ?? 'Product',
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------- Orders (with status actions) ----------------
class _SellerOrdersTab extends ConsumerWidget {
  const _SellerOrdersTab();

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    String id,
    String status,
  ) async {
    try {
      await ApiClient.dio.patch('/orders/$id/status', data: {'status': status});
      ref.invalidate(ordersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order marked as ${status.replaceAll('_', ' ')}')),
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
      child: ResponsiveContainer(
        maxWidth: Breakpoints.desktop,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Orders Received', style: serif(20)),
                  const Text(
                    'Track fulfillment and progress orders step by step',
                    style: TextStyle(fontSize: 12, color: MMColors.muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: orders.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                  message: apiError(e),
                  onRetry: () => ref.invalidate(ordersProvider),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyView(message: 'No orders yet.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final o = items[i];
                          final status = o['status'].toString();
                          final next = nextStep[status];
                          final amounts = (o['amounts'] as Map?) ?? {};
                          final itemsList = (o['items'] as List?) ?? [];
                          final customer = (o['customer'] as Map?) ?? {};

                          return Container(
                            decoration: BoxDecoration(
                              color: MMColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: MMColors.sand),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x06000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          o['orderNumber']?.toString() ?? 'Order',
                                          style: serif(16, weight: FontWeight.w700),
                                        ),
                                        if (customer['name'] != null)
                                          Text(
                                            'Customer: ${customer['name']}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: MMColors.muted,
                                            ),
                                          ),
                                      ],
                                    ),
                                    Text(
                                      rupees(amounts['total']),
                                      style: serif(
                                        17,
                                        color: MMColors.olive,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: itemsList.map((it) {
                                    final item = it as Map;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• ${item['name']} × ${item['quantity']}  (${rupees(item['price'])})',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _orderStatusColor(status).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status.replaceAll('_', ' ').toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _orderStatusColor(status),
                                        ),
                                      ),
                                    ),
                                    if (next != null)
                                      FilledButton.icon(
                                        icon: const Icon(Icons.arrow_forward, size: 16),
                                        onPressed: () => _transition(
                                          context,
                                          ref,
                                          o['_id'].toString(),
                                          next,
                                        ),
                                        label: Text(
                                          next == 'confirmed'
                                              ? 'Confirm Order'
                                              : 'Mark ${next.replaceAll('_', ' ')}',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
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
      child: ResponsiveContainer(
        maxWidth: Breakpoints.desktop,
        child: orders.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: apiError(e)),
          data: (items) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Earnings & Revenue', style: serif(22)),
              const SizedBox(height: 4),
              const Text(
                'Financial summary based on completed deliveries',
                style: TextStyle(color: MMColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isSmall = constraints.maxWidth < 600;
                  return GridView.count(
                    crossAxisCount: isSmall ? 2 : 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: isSmall ? 1.5 : 1.7,
                    children: [
                      _StatCard(
                        label: 'Today',
                        value: rupees(_earnings(items, window: const Duration(days: 1))),
                        icon: Icons.today,
                        accentColor: MMColors.olive,
                      ),
                      _StatCard(
                        label: 'This Week',
                        value: rupees(_earnings(items, window: const Duration(days: 7))),
                        icon: Icons.date_range,
                        accentColor: MMColors.terracotta,
                      ),
                      _StatCard(
                        label: 'This Month',
                        value: rupees(_earnings(items, window: const Duration(days: 30))),
                        icon: Icons.calendar_month,
                        accentColor: const Color(0xFF1565C0),
                      ),
                      _StatCard(
                        label: 'All Time',
                        value: rupees(_earnings(items)),
                        icon: Icons.savings_outlined,
                        accentColor: MMColors.marigold,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MMColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MMColors.sand),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: MMColors.cream,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.info_outline, color: MMColors.olive),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payout Information',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Earnings are calculated from delivered customer orders. Direct payouts to your verified bank account are processed on a weekly schedule.',
                            style: TextStyle(color: MMColors.muted, fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Bank Details for Payouts', style: serif(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: holder,
              decoration: const InputDecoration(labelText: 'Account Holder Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: account,
              decoration: const InputDecoration(labelText: 'Account Number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ifsc,
              decoration: const InputDecoration(labelText: 'IFSC Code'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Details')),
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bank details updated')),
        );
      }
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final password = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Change Password', style: serif(18)),
        content: TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password (min 6 chars)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
        ],
      ),
    );
    if (saved == true && password.text.length >= 6) {
      final username = ref.read(authProvider).user?['username']?.toString() ?? '';
      await ref.read(authProvider.notifier).setCredentials(username, password.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final shops = ref.watch(myBusinessesProvider);
    final shop = shops.asData?.value.isNotEmpty == true
        ? shops.asData!.value.first
        : null;
    final shopId = shop?['_id']?.toString();

    return SafeArea(
      child: ResponsiveContainer(
        maxWidth: 680,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 12),
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: MMColors.olive,
                    backgroundImage: (auth.user?['avatarUrl'] != null)
                        ? NetworkImage(auth.user!['avatarUrl'].toString())
                        : null,
                    child: (auth.user?['avatarUrl'] == null)
                        ? Text(
                            auth.name.isNotEmpty ? auth.name[0].toUpperCase() : 'S',
                            style: serif(32, color: Colors.white, weight: FontWeight.w700),
                          )
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(child: Text(auth.name, style: serif(22, color: MMColors.ink))),
            Center(
              child: Text(
                auth.email,
                style: const TextStyle(fontSize: 13, color: MMColors.muted),
              ),
            ),
            if (shop != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${shop['name']} · Verified Seller',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Profile Actions
            Container(
              decoration: BoxDecoration(
                color: MMColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MMColors.sand),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined, color: MMColors.olive),
                    title: const Text('Business Profile'),
                    subtitle: Text(
                      shop?['name']?.toString() ?? 'View your store details',
                      style: const TextStyle(fontSize: 12, color: MMColors.muted),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        title: Text('Business Profile', style: serif(18)),
                        content: shop == null
                            ? const Text('No business details yet.')
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(shop['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 6),
                                  Text('Category: ${shop['category'] ?? '-'}'),
                                  Text('Experience: ${shop['yearsOfExperience'] ?? '-'} years'),
                                  const SizedBox(height: 8),
                                  Text(shop['description']?.toString() ?? ''),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.account_balance_outlined, color: MMColors.olive),
                    title: const Text('Bank & Payouts'),
                    subtitle: const Text(
                      'Account details for receiving order revenues',
                      style: TextStyle(fontSize: 12, color: MMColors.muted),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _bankDetails(context, ref),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined, color: MMColors.olive),
                    title: const Text('Kitchen / Workshop Address'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) {
                        final address = (shop?['address'] as Map?) ?? {};
                        return AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          title: Text('Business Address', style: serif(18)),
                          content: Text(
                            '${address['line1'] ?? 'No address registered'}\n'
                            '${address['city'] ?? ''} ${address['postalCode'] ?? ''}',
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_outline, color: MMColors.olive),
                    title: const Text('Security & Password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changePassword(context, ref),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.rate_review_outlined, color: MMColors.olive),
                    title: const Text('Customer Reviews'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: shopId == null
                        ? null
                        : () => showDialog(
                              context: context,
                              builder: (ctx) => Dialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 460, maxHeight: 480),
                                  child: Consumer(builder: (c, r, _) {
                                    final reviews = r.watch(businessReviewsProvider(shopId));
                                    return reviews.when(
                                      loading: () => const Center(child: CircularProgressIndicator()),
                                      error: (e, _) => Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(apiError(e)),
                                      ),
                                      data: (items) => items.isEmpty
                                          ? const Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Text('No reviews yet.'),
                                            )
                                          : ListView(
                                              padding: const EdgeInsets.all(16),
                                              children: items.map((rv) {
                                                return ListTile(
                                                  leading: const Icon(
                                                    Icons.star,
                                                    color: MMColors.marigold,
                                                  ),
                                                  title: Text(
                                                    '${rv['rating']} ★ · ${(rv['customer'] as Map?)?['name'] ?? 'Customer'}',
                                                  ),
                                                  subtitle: Text(rv['comment']?.toString() ?? ''),
                                                );
                                              }).toList(),
                                            ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz, color: MMColors.terracotta),
                    title: const Text('Switch to Customer Mode'),
                    subtitle: const Text('Browse marketplace and place orders'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await ref.read(authProvider.notifier).switchRole('customer');
                      ref.invalidate(ordersProvider);
                      ref.invalidate(cartProvider);
                      if (context.mounted) context.go('/app');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Color(0xFFC62828)),
                    title: const Text('Logout', style: TextStyle(color: Color(0xFFC62828))),
                    onTap: () {
                      ref.read(authProvider.notifier).logout();
                      context.go('/');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
