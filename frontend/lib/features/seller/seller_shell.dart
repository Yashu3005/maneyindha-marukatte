import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

/// Entrepreneur Shell conforming to the Figma specification:
/// Bottom Navigation: Home/Dashboard | Orders | Products | Earnings | Profile
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
      backgroundColor: MMColors.warmIvory,
      body: IndexedStack(
        index: _index,
        children: [
          _DashboardTab(onViewAllOrders: () => setState(() => _index = 1)),
          const _SellerOrdersTab(),
          const _ProductsTab(),
          const _EarningsTab(),
          const _SellerProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: MMColors.cream,
        indicatorColor: MMColors.sage,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: MMColors.primaryGreen),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: MMColors.primaryGreen),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2, color: MMColors.primaryGreen),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: MMColors.primaryGreen),
            label: 'Earnings',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: MMColors.primaryGreen),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

String? _shopId(List<Map<String, dynamic>> shops) =>
    shops.isEmpty ? null : shops.first['_id'].toString();

// ---------------- 1. Dashboard Tab ----------------
class _DashboardTab extends ConsumerWidget {
  final VoidCallback onViewAllOrders;
  const _DashboardTab({required this.onViewAllOrders});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final shops = ref.watch(myBusinessesProvider);
    final ordersAsync = ref.watch(ordersProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header: Avatar, Name & Welcome
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: MMColors.sage,
                backgroundImage: (auth.user?['avatarUrl'] != null)
                    ? NetworkImage(auth.user!['avatarUrl'].toString())
                    : null,
                child: (auth.user?['avatarUrl'] == null)
                    ? const Icon(Icons.person, color: MMColors.primaryGreen)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome, ${auth.name.isNotEmpty ? auth.name.split(' ').first : 'Entrepreneur'}',
                        style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                    const Text('Grow your business with confidence 🌸',
                        style: TextStyle(color: MMColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_none, color: MMColors.primaryGreen),
                onPressed: () => context.push('/notifications'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Business Overview: 4 Summary Cards
          shops.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(message: apiError(e)),
            data: (myShops) {
              final shopId = _shopId(myShops);
              final products = shopId == null
                  ? const AsyncValue.data(<Map<String, dynamic>>[])
                  : ref.watch(productsProvider(shopId));

              return ordersAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => const SizedBox(),
                data: (allOrders) {
                  final now = DateTime.now();
                  final todayOrders = allOrders.where((o) {
                    final created = DateTime.tryParse(o['createdAt']?.toString() ?? '');
                    return created != null && created.day == now.day && created.month == now.month;
                  }).toList();

                  num monthEarnings = 0;
                  for (final o in allOrders) {
                    if (o['status'] == 'delivered') {
                      monthEarnings += ((o['amounts'] as Map?)?['total'] ?? 0) as num;
                    }
                  }

                  final pendingCount = allOrders.where((o) => ['pending', 'confirmed', 'preparing'].contains(o['status'])).length;
                  final activeProductsCount = products.maybeWhen(
                    data: (pList) => pList.where((p) => p['isActive'] != false && (p['stock'] ?? 0) > 0).length,
                    orElse: () => 0,
                  );

                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                    children: [
                      _StatCard(label: "Today's Orders", value: '${todayOrders.length}', icon: Icons.receipt),
                      _StatCard(label: "This Month's Earnings", value: rupees(monthEarnings), icon: Icons.currency_rupee),
                      _StatCard(label: 'Active Products', value: '$activeProductsCount', icon: Icons.inventory_2),
                      _StatCard(label: 'Pending Orders', value: '$pendingCount', icon: Icons.pending_actions),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),

          // Today's Recent Orders Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Today's Recent Orders",
                  style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
              TextButton(
                onPressed: onViewAllOrders,
                child: const Text('View All >',
                    style: TextStyle(color: MMColors.primaryGreen, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Recent Orders List
          ordersAsync.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(message: apiError(e)),
            data: (allOrders) {
              if (allOrders.isEmpty) {
                return Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: MMColors.sage, width: 0.8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.inbox_outlined, size: 48, color: MMColors.secondaryGreen),
                          SizedBox(height: 8),
                          Text('No Orders Yet', style: TextStyle(fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text('New customer orders will appear here.',
                              style: TextStyle(color: MMColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: allOrders.take(4).map((o) {
                  final status = o['status']?.toString() ?? 'pending';
                  final items = (o['items'] as List?) ?? [];
                  final custName = (o['customer'] is Map) ? o['customer']['name'] : 'Customer';

                  return Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: MMColors.sage, width: 0.8),
                    ),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('$custName • #${o['orderNumber'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text('${items.length} ${items.length == 1 ? 'item' : 'items'} • ${rupees(o['amounts']?['total'])}',
                          style: const TextStyle(color: MMColors.textSecondary, fontSize: 12)),
                      trailing: Chip(
                        label: Text(status.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 10)),
                        backgroundColor: status == 'delivered'
                            ? Colors.green.shade100
                            : status == 'cancelled'
                                ? Colors.red.shade100
                                : MMColors.sage,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: MMColors.sage, width: 0.8),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: MMColors.primaryGreen),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: MMColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 2. Orders Tab (with After-Sales Requests) ----------------
class _SellerOrdersTab extends ConsumerStatefulWidget {
  const _SellerOrdersTab();

  @override
  ConsumerState<_SellerOrdersTab> createState() => _SellerOrdersTabState();
}

class _SellerOrdersTabState extends ConsumerState<_SellerOrdersTab> {
  String _statusFilter = 'All'; // All, New, Preparing, Out for Delivery, Delivered, After-Sales
  bool _showAfterSales = false;

  Future<void> _updateStatus(String orderId, String nextStatus) async {
    try {
      await ApiClient.dio.patch('/orders/$orderId/status', data: {'status': nextStatus});
      ref.invalidate(ordersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order updated to ${nextStatus.replaceAll('_', ' ')}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _decideAfterSales(String orderId, String decision, bool returnReq) async {
    try {
      await ApiClient.dio.post('/orders/$orderId/after-sales/decide', data: {
        'decision': decision,
        'returnRequired': returnReq,
      });
      ref.invalidate(ordersProvider);
      ref.invalidate(afterSalesRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request $decision')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _confirmReturn(String orderId) async {
    try {
      await ApiClient.dio.post('/orders/$orderId/return/confirm');
      ref.invalidate(ordersProvider);
      ref.invalidate(afterSalesRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return receipt confirmed!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);
    final afterSalesAsync = ref.watch(afterSalesRequestsProvider);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text('Orders Management',
                    style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                const Spacer(),
                ChoiceChip(
                  label: const Text('After-Sales'),
                  selected: _showAfterSales,
                  selectedColor: MMColors.primaryGreen,
                  labelStyle: TextStyle(
                    color: _showAfterSales ? Colors.white : MMColors.primaryGreen,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (val) => setState(() => _showAfterSales = val),
                ),
              ],
            ),
          ),

          if (!_showAfterSales)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: ['All', 'New', 'Preparing', 'Out for Delivery', 'Delivered'].map((chip) {
                  final isSelected = _statusFilter == chip;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(chip),
                      selected: isSelected,
                      selectedColor: MMColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : MMColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      onSelected: (_) => setState(() => _statusFilter = chip),
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),

          Expanded(
            child: _showAfterSales
                ? afterSalesAsync.when(
                    loading: () => const LoadingView(),
                    error: (e, _) => ErrorView(message: apiError(e)),
                    data: (requests) {
                      if (requests.isEmpty) {
                        return const Center(child: Text('No after-sales requests pending.'));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final r = requests[i];
                          final id = r['_id']?.toString() ?? '';
                          final af = (r['afterSales'] as Map?) ?? {};
                          final status = af['status'] ?? 'requested';
                          final returnStatus = af['returnStatus'] ?? 'none';
                          final aiSuggestion = af['aiSuggestion'] ?? 'Analyze customer explanation';

                          return Card(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: MMColors.sage, width: 0.8),
                            ),
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Order #${r['orderNumber'] ?? ''}',
                                          style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Chip(label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 10))),
                                    ],
                                  ),
                                  Text('Type: ${af['type'] == 'refund' ? 'Refund Request' : 'Replacement Request'}',
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('Reason: ${af['reason'] ?? ''}', style: const TextStyle(fontSize: 13)),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: MMColors.cream,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.psychology, size: 18, color: MMColors.primaryGreen),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text('AI Suggestion: $aiSuggestion',
                                              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (status == 'requested' || status == 'in_review')
                                    Row(
                                      children: [
                                        FilledButton(
                                          style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                                          onPressed: () => _decideAfterSales(id, 'approved', true),
                                          child: const Text('Approve (Return Req)'),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                                          onPressed: () => _decideAfterSales(id, 'rejected', false),
                                          child: const Text('Reject', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  if (returnStatus == 'return_initiated') ...[
                                    const SizedBox(height: 8),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                                      onPressed: () => _confirmReturn(id),
                                      child: const Text('Confirm Return Received'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  )
                : ordersAsync.when(
                    loading: () => const LoadingView(),
                    error: (e, _) => ErrorView(message: apiError(e)),
                    data: (items) {
                      final filtered = items.where((o) {
                        final s = o['status']?.toString() ?? '';
                        if (_statusFilter == 'New') return s == 'pending';
                        if (_statusFilter == 'Preparing') return s == 'confirmed' || s == 'preparing';
                        if (_statusFilter == 'Out for Delivery') return s == 'out_for_delivery' || s == 'ready';
                        if (_statusFilter == 'Delivered') return s == 'delivered';
                        return true;
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(child: Text('No orders found in this category.'));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final o = filtered[i];
                          final id = o['_id']?.toString() ?? '';
                          final status = o['status']?.toString() ?? 'pending';
                          final isPickup = o['isSelfPickup'] == true;
                          final orderItems = (o['items'] as List?) ?? [];

                          String? nextLabel;
                          String? nextStatus;

                          if (status == 'pending') {
                            nextLabel = 'Accept Order';
                            nextStatus = 'confirmed';
                          } else if (status == 'confirmed') {
                            nextLabel = 'Preparing Order';
                            nextStatus = 'preparing';
                          } else if (status == 'preparing') {
                            nextLabel = isPickup ? 'Ready for Pickup' : 'Out for Delivery';
                            nextStatus = isPickup ? 'ready' : 'out_for_delivery';
                          } else if (status == 'ready' || status == 'out_for_delivery') {
                            nextLabel = isPickup ? 'Mark as Picked Up' : 'Mark as Delivered';
                            nextStatus = 'delivered';
                          }

                          return Card(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: MMColors.sage, width: 0.8),
                            ),
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('#${o['orderNumber'] ?? ''}',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      Chip(
                                        label: Text(status.replaceAll('_', ' ').toUpperCase(),
                                            style: const TextStyle(fontSize: 10)),
                                        backgroundColor: status == 'delivered'
                                            ? Colors.green.shade100
                                            : MMColors.sage,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    orderItems
                                        .map((it) => '${(it as Map)['name']} × ${it['quantity']}')
                                        .join(', '),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Total: ${rupees(o['amounts']?['total'])} • ${isPickup ? 'Self Pickup' : 'Home Delivery'}',
                                    style: const TextStyle(color: MMColors.textSecondary, fontSize: 12),
                                  ),
                                  if (nextLabel != null && nextStatus != null) ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: MMColors.primaryGreen,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _updateStatus(id, nextStatus!),
                                        child: Text(nextLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 3. Products Tab (Product Management) ----------------
class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab();

  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab> {
  void _openAddEditProductSheet(String businessId, [Map<String, dynamic>? existing]) {
    final isEdit = existing != null;
    final productId = existing?['_id']?.toString();

    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: existing?['price']?.toString() ?? '');
    final stockCtrl = TextEditingController(text: existing?['stock']?.toString() ?? '10');
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    final deliveryRadiusCtrl = TextEditingController(
        text: existing?['deliveryOptions']?['deliveryRadius']?.toString() ?? '5');
    final deliveryChargeCtrl = TextEditingController(
        text: existing?['deliveryOptions']?['deliveryCharge']?.toString() ?? '30');

    String selectedSupport = existing?['afterSales']?['supportType'] ?? 'replacement_only';
    String selectedWindow = existing?['afterSales']?['supportWindow'] ?? '3 Days';
    bool returnRequired = existing?['afterSales']?['returnRequired'] == true;
    bool homeDelivery = existing?['deliveryOptions']?['homeDelivery'] != false;
    bool pickup = existing?['deliveryOptions']?['pickup'] != false;

    final images = List<String>.from((existing?['images'] as List?) ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: MMColors.warmIvory,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.6,
          expand: false,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isEdit ? 'Edit Product' : 'Add Product',
                      style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(),

              // Product Name with AI Improve Title
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Product Name *'),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16, color: MMColors.primaryGreen),
                  label: const Text('Improve Title (AI)', style: TextStyle(color: MMColors.primaryGreen)),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    try {
                      final res = await ApiClient.dio.post('/products/ai/improve-title', data: {'title': nameCtrl.text.trim()});
                      final sug = res.data['data']['suggestedTitle'];
                      if (sug != null) setSheetState(() => nameCtrl.text = sug);
                    } catch (_) {}
                  },
                ),
              ),
              const SizedBox(height: 8),

              // Price with AI Suggest Price
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Price (₹) *'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 16, color: MMColors.primaryGreen),
                    label: const Text('Suggest Price', style: TextStyle(color: MMColors.primaryGreen)),
                    onPressed: () async {
                      try {
                        final res = await ApiClient.dio.post('/products/ai/suggest-price', data: {'name': nameCtrl.text.trim()});
                        final sug = res.data['data']['suggestedPrice'];
                        if (sug != null) setSheetState(() => priceCtrl.text = '$sug');
                      } catch (_) {}
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Stock Quantity
              TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Available Stock Quantity *'),
              ),
              const SizedBox(height: 12),

              // Description with AI Description Generator
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description *'),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16, color: MMColors.primaryGreen),
                  label: const Text('Generate Description (AI)', style: TextStyle(color: MMColors.primaryGreen)),
                  onPressed: () async {
                    try {
                      final res = await ApiClient.dio.post('/products/ai/generate-description', data: {'name': nameCtrl.text.trim()});
                      final sug = res.data['data']['generatedDescription'];
                      if (sug != null) setSheetState(() => descCtrl.text = sug);
                    } catch (_) {}
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Delivery Options
              Text('Delivery Method', style: serif(16, color: MMColors.primaryGreen)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Home Delivery'),
                value: homeDelivery,
                onChanged: (v) => setSheetState(() => homeDelivery = v ?? true),
              ),
              if (homeDelivery) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: deliveryRadiusCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Delivery Radius (km)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: deliveryChargeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Delivery Charge (₹)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pickup Available'),
                value: pickup,
                onChanged: (v) => setSheetState(() => pickup = v ?? true),
              ),
              const SizedBox(height: 12),

              // After Sales Support
              Text('After-Sales Support', style: serif(16, color: MMColors.primaryGreen)),
              DropdownButtonFormField<String>(
                initialValue: selectedSupport,
                decoration: const InputDecoration(labelText: 'Support Policy'),
                items: const [
                  DropdownMenuItem(value: 'not_available', child: Text('Not Available')),
                  DropdownMenuItem(value: 'replacement_only', child: Text('Replacement Only')),
                  DropdownMenuItem(value: 'return_and_replacement', child: Text('Return & Replacement')),
                ],
                onChanged: (v) => setSheetState(() => selectedSupport = v ?? 'not_available'),
              ),
              if (selectedSupport != 'not_available') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedWindow,
                  decoration: const InputDecoration(labelText: 'Support Window'),
                  items: ['24 Hours', '3 Days', '7 Days']
                      .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => selectedWindow = v ?? '3 Days'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Physical Return Required before Refund/Replacement'),
                  value: returnRequired,
                  onChanged: (v) => setSheetState(() => returnRequired = v ?? false),
                ),
              ],
              const SizedBox(height: 24),

              // Save / Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;

                    final body = {
                      'business': businessId,
                      'name': nameCtrl.text.trim(),
                      'price': num.tryParse(priceCtrl.text) ?? 0,
                      'stock': num.tryParse(stockCtrl.text) ?? 10,
                      'description': descCtrl.text.trim(),
                      'images': images.isNotEmpty ? images : ['https://picsum.photos/seed/${nameCtrl.text}/500/400'],
                      'deliveryOptions': {
                        'homeDelivery': homeDelivery,
                        'pickup': pickup,
                        'deliveryRadius': num.tryParse(deliveryRadiusCtrl.text) ?? 5,
                        'deliveryCharge': num.tryParse(deliveryChargeCtrl.text) ?? 30,
                      },
                      'afterSales': {
                        'supportType': selectedSupport,
                        'supportWindow': selectedWindow,
                        'returnRequired': returnRequired,
                      },
                    };

                    try {
                      if (isEdit && productId != null) {
                        await ApiClient.dio.patch('/products/$productId', data: body);
                      } else {
                        await ApiClient.dio.post('/products', data: body);
                      }
                      ref.invalidate(productsProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isEdit ? 'Product Updated Successfully' : 'Product Added Successfully')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                      }
                    }
                  },
                  child: Text(isEdit ? 'Save Changes' : 'Add Product', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUpdateStockDialog(Map<String, dynamic> product) {
    int currentStock = (product['stock'] ?? 0) as int;
    final id = product['_id']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Update Stock: ${product['name']}', style: serif(18, color: MMColors.primaryGreen)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Adjust current inventory count:'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 32, color: MMColors.primaryGreen),
                    onPressed: currentStock > 0 ? () => setDialogState(() => currentStock--) : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('$currentStock', style: serif(28, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 32, color: MMColors.primaryGreen),
                    onPressed: () => setDialogState(() => currentStock++),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(currentStock > 0 ? 'Status: In Stock' : 'Status: Out of Stock',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: currentStock > 0 ? Colors.green : Colors.red)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () async {
                try {
                  await ApiClient.dio.patch('/products/$id/stock', data: {
                    'stock': currentStock,
                    'inStock': currentStock > 0,
                  });
                  ref.invalidate(productsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Stock Updated Successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Save Stock'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> product) {
    final id = product['_id']?.toString() ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MMColors.warmIvory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Product?'),
        content: Text('Are you sure you want to delete "${product['name']}"? This will remove it from customer listings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              try {
                await ApiClient.dio.delete('/products/$id');
                ref.invalidate(productsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Product Deleted Successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              }
            },
            child: const Text('Delete Product'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shops = ref.watch(myBusinessesProvider);

    return SafeArea(
      child: shops.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e)),
        data: (myShops) {
          final shopId = _shopId(myShops);
          if (shopId == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No business found on this account.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.go('/seller/onboarding/business'),
                    child: const Text('Set up your business'),
                  ),
                ],
              ),
            );
          }

          final productsAsync = ref.watch(productsProvider(shopId));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('My Products', style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: MMColors.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _openAddEditProductSheet(shopId),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('+ Add Product'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: productsAsync.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(message: apiError(e)),
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 64, color: MMColors.secondaryGreen),
                            const SizedBox(height: 12),
                            const Text('No Products Added Yet\nStart selling by adding your first product.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: MMColors.textSecondary, fontSize: 14)),
                            const SizedBox(height: 16),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                              onPressed: () => _openAddEditProductSheet(shopId),
                              child: const Text('+ Add Product'),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final p = items[i];
                        final images = (p['images'] as List?) ?? [];
                        final firstImg = images.isNotEmpty ? images.first.toString() : null;
                        final stock = (p['stock'] ?? 0) as num;

                        return Card(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: MMColors.sage, width: 0.8),
                          ),
                          elevation: 0,
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(width: 56, height: 56, child: NetImage(firstImg)),
                            ),
                            title: Text(p['name']?.toString() ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            subtitle: Text(
                              '${rupees(p['price'])} • Stock: $stock ${stock > 0 ? '(Active)' : '(Out of Stock)'}',
                              style: TextStyle(
                                  color: stock > 0 ? MMColors.primaryGreen : Colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: MMColors.primaryGreen),
                              onSelected: (action) {
                                if (action == 'edit') {
                                  _openAddEditProductSheet(shopId, p);
                                } else if (action == 'stock') {
                                  _showUpdateStockDialog(p);
                                } else if (action == 'delete') {
                                  _showDeleteDialog(p);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('✏ Edit Product')),
                                const PopupMenuItem(value: 'stock', child: Text('Update Stock')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete Product')),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------- 4. Earnings Tab (with single Bar Chart & AI Insights) ----------------
class _EarningsTab extends ConsumerStatefulWidget {
  const _EarningsTab();

  @override
  ConsumerState<_EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends ConsumerState<_EarningsTab> {
  String _timeFilter = 'This Month'; // Today, This Week, This Month

  @override
  Widget build(BuildContext context) {
    final shops = ref.watch(myBusinessesProvider);
    final shopId = shops.asData?.value.isNotEmpty == true ? shops.asData!.value.first['_id'].toString() : null;

    if (shopId == null) {
      return const Center(child: Text('No business found.'));
    }

    final insightsAsync = ref.watch(entrepreneurInsightsProvider(shopId));

    return SafeArea(
      child: insightsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e)),
        data: (data) {
          final totalEarnings = (data['totalEarnings'] ?? 0) as num;
          final completedOrders = (data['completedOrders'] ?? 0) as num;
          final avgOrderValue = (data['avgOrderValue'] ?? 0) as num;
          final bestSeller = data['bestSellingProduct']?.toString() ?? 'None';
          final insights = (data['insights'] as List?) ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Earnings & Performance',
                  style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
              const SizedBox(height: 12),

              // Time Filters
              Row(
                children: ['Today', 'This Week', 'This Month'].map((f) {
                  final isSelected = _timeFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: isSelected,
                      selectedColor: MMColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : MMColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      onSelected: (_) => setState(() => _timeFilter = f),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Total Earnings Card
              Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: MMColors.sage, width: 0.8),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Earnings',
                          style: TextStyle(color: MMColors.textSecondary, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(rupees(totalEarnings),
                          style: serif(30, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Earnings Single Bar Chart
              Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: MMColors.sage, width: 0.8),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Earnings Trend ($_timeFilter)',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 120,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _bar('Mon', 0.4),
                            _bar('Tue', 0.6),
                            _bar('Wed', 0.3),
                            _bar('Thu', 0.8),
                            _bar('Fri', 0.5),
                            _bar('Sat', 0.95),
                            _bar('Sun', 0.85),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Business Summary Cards
              Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: MMColors.sage, width: 0.8),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Business Summary',
                          style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Completed Orders', style: TextStyle(color: MMColors.textSecondary)),
                          Text('$completedOrders', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Best Selling Product', style: TextStyle(color: MMColors.textSecondary)),
                          Text(bestSeller, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Average Order Value', style: TextStyle(color: MMColors.textSecondary)),
                          Text(rupees(avgOrderValue), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // AI Business Insights Card
              Card(
                color: MMColors.cream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: MMColors.sage, width: 0.8),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: MMColors.primaryGreen, size: 20),
                          const SizedBox(width: 8),
                          Text('AI Business Insights',
                              style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...insights.map((ins) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                Expanded(child: Text(ins.toString(), style: const TextStyle(fontSize: 13))),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(String day, double fraction) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 22,
          height: 90 * fraction,
          decoration: BoxDecoration(
            color: MMColors.primaryGreen,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(day, style: const TextStyle(fontSize: 11, color: MMColors.textSecondary)),
      ],
    );
  }
}

// ---------------- 5. Entrepreneur Profile Tab ----------------
class _SellerProfileTab extends ConsumerWidget {
  const _SellerProfileTab();

  void _showAvailabilityDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> shop) {
    bool isOpen = shop['isOpen'] != false;
    final id = shop['_id']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Store Availability', style: serif(18, color: MMColors.primaryGreen)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Store Open for Orders', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(isOpen ? 'Customers can place orders' : 'Store closed; ordering disabled'),
                value: isOpen,
                onChanged: (val) => setDialogState(() => isOpen = val),
              ),
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Weekly Schedule: Monday - Sunday (9:00 AM - 8:00 PM)',
                    style: TextStyle(fontSize: 12, color: MMColors.textSecondary)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () async {
                try {
                  await ApiClient.dio.patch('/businesses/$id/availability', data: {'isOpen': isOpen});
                  ref.invalidate(myBusinessesProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Store is now ${isOpen ? 'Open' : 'Closed'}')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Save Availability'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentSettingsDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> shop) {
    final bank = (shop['bankAccount'] as Map?) ?? {};
    final holderCtrl = TextEditingController(text: bank['accountHolderName']?.toString() ?? '');
    final bankNameCtrl = TextEditingController(text: bank['bankName']?.toString() ?? '');
    final accCtrl = TextEditingController(text: bank['accountNumber']?.toString() ?? '');
    final ifscCtrl = TextEditingController(text: bank['ifscCode']?.toString() ?? '');
    final upiCtrl = TextEditingController(text: bank['upiId']?.toString() ?? '');
    final id = shop['_id']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MMColors.warmIvory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Payment Settings', style: serif(18, color: MMColors.primaryGreen)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: holderCtrl, decoration: const InputDecoration(labelText: 'Account Holder Name *')),
              const SizedBox(height: 10),
              TextField(controller: bankNameCtrl, decoration: const InputDecoration(labelText: 'Bank Name *')),
              const SizedBox(height: 10),
              TextField(controller: accCtrl, decoration: const InputDecoration(labelText: 'Bank Account Number *')),
              const SizedBox(height: 10),
              TextField(controller: ifscCtrl, decoration: const InputDecoration(labelText: 'IFSC Code (e.g. SBIN0001234) *')),
              const SizedBox(height: 10),
              TextField(controller: upiCtrl, decoration: const InputDecoration(labelText: 'UPI ID (e.g. name@okaxis) *')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
            onPressed: () async {
              try {
                await ApiClient.dio.patch('/businesses/$id/payment-settings', data: {
                  'accountHolderName': holderCtrl.text.trim(),
                  'bankName': bankNameCtrl.text.trim(),
                  'accountNumber': accCtrl.text.trim(),
                  'ifscCode': ifscCtrl.text.trim(),
                  'upiId': upiCtrl.text.trim(),
                });
                ref.invalidate(myBusinessesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payment details saved successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              }
            },
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final shops = ref.watch(myBusinessesProvider);
    final shop = shops.asData?.value.isNotEmpty == true ? shops.asData!.value.first : null;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: MMColors.sage,
              backgroundImage: (auth.user?['avatarUrl'] != null)
                  ? NetworkImage(auth.user!['avatarUrl'].toString())
                  : null,
              child: (auth.user?['avatarUrl'] == null)
                  ? const Icon(Icons.person, size: 44, color: MMColors.primaryGreen)
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          Center(child: Text(auth.name, style: serif(22, color: MMColors.primaryGreen))),
          Center(
            child: Text(shop != null ? '${shop['name']} ✓' : 'Entrepreneur',
                style: const TextStyle(color: MMColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: MMColors.sage, width: 0.8),
            ),
            elevation: 0,
            child: Column(
              children: [
                if (shop != null) ...[
                  ListTile(
                    leading: const Icon(Icons.schedule, color: MMColors.primaryGreen),
                    title: const Text('Business Availability & Schedule', style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                    onTap: () => _showAvailabilityDialog(context, ref, shop),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.account_balance, color: MMColors.primaryGreen),
                    title: const Text('Payment Settings (Bank & UPI)', style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                    onTap: () => _showPaymentSettingsDialog(context, ref, shop),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.shopping_bag_outlined, color: MMColors.primaryGreen),
                  title: const Text('Switch to Customer Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                  onTap: () async {
                    await ref.read(authProvider.notifier).switchRole('customer');
                    ref.invalidate(ordersProvider);
                    ref.invalidate(cartProvider);
                    if (context.mounted) context.go('/app');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                  onTap: () {
                    ref.read(authProvider.notifier).logout();
                    context.go('/');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
