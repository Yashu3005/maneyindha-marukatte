import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

/// Full Admin Module conforming to the Figma specification:
/// Primary Navigation: Dashboard | Entrepreneurs | Products | Support Center | Profile
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isAdmin) {
      return Scaffold(
        backgroundColor: MMColors.warmIvory,
        appBar: AppBar(
          backgroundColor: MMColors.warmIvory,
          title: Text('Admin Access Required', style: serif(18, color: MMColors.primaryGreen)),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 72, color: MMColors.secondaryGreen),
              const SizedBox(height: 16),
              const Text('Please sign in with administrator credentials.'),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                onPressed: () => context.go('/login'),
                child: const Text('Sign in as Admin'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      body: IndexedStack(
        index: _navIndex,
        children: [
          _AdminDashboardTab(
            onOpenVerifications: () => setState(() => _navIndex = 1),
            onOpenSupport: () => setState(() => _navIndex = 3),
          ),
          const _AdminEntrepreneursTab(),
          const _AdminProductsTab(),
          const _AdminSupportTab(),
          const _AdminProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: MMColors.cream,
        indicatorColor: MMColors.sage,
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: MMColors.primaryGreen),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: MMColors.primaryGreen),
            label: 'Entrepreneurs',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2, color: MMColors.primaryGreen),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent, color: MMColors.primaryGreen),
            label: 'Support',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield, color: MMColors.primaryGreen),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ---------------- 1. Dashboard Tab ----------------
class _AdminDashboardTab extends ConsumerWidget {
  final VoidCallback onOpenVerifications;
  final VoidCallback onOpenSupport;

  const _AdminDashboardTab({
    required this.onOpenVerifications,
    required this.onOpenSupport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Admin Dashboard',
              style: serif(22, color: MMColors.primaryGreen, weight: FontWeight.w700)),
          const Text('Overview of platform operations today',
              style: TextStyle(color: MMColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),

          statsAsync.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              message: 'Could not load stats.',
              onRetry: () => ref.invalidate(adminStatsProvider),
            ),
            data: (stats) {
              final entrepreneurs = stats['totalEntrepreneurs'] ?? 0;
              final customers = stats['totalCustomers'] ?? 0;
              final products = stats['totalProducts'] ?? 0;
              final orders = stats['totalOrders'] ?? 0;
              final pending = stats['pendingApprovals'] ?? 0;
              final openTickets = stats['openTickets'] ?? 0;
              final complaints = stats['activeComplaints'] ?? 0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Platform Overview', style: serif(16, color: MMColors.primaryGreen)),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.5,
                    children: [
                      _adminMetric('Total Entrepreneurs', '$entrepreneurs', Icons.storefront),
                      _adminMetric('Total Customers', '$customers', Icons.people_outline),
                      _adminMetric('Total Products', '$products', Icons.inventory_2_outlined),
                      _adminMetric('Total Orders', '$orders', Icons.receipt_long_outlined),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Actionable Platform Status Cards
                  Text('Platform Status (Requires Action)',
                      style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                  const SizedBox(height: 8),

                  Card(
                    color: pending > 0 ? MMColors.cream : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: MMColors.sage, width: 0.8),
                    ),
                    elevation: 0,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: MMColors.sage,
                        child: Icon(Icons.verified_user_outlined, color: MMColors.primaryGreen),
                      ),
                      title: Text('Pending Entrepreneur Approvals: $pending',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Review verification documents and store profiles'),
                      trailing: const Icon(Icons.chevron_right, color: MMColors.primaryGreen),
                      onTap: onOpenVerifications,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: MMColors.sage, width: 0.8),
                    ),
                    elevation: 0,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: MMColors.sage,
                        child: Icon(Icons.help_outline, color: MMColors.primaryGreen),
                      ),
                      title: Text('Open Support Tickets: $openTickets',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Respond to customer account, order, and appeal tickets'),
                      trailing: const Icon(Icons.chevron_right, color: MMColors.primaryGreen),
                      onTap: onOpenSupport,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Card(
                    color: complaints > 0 ? Colors.red.shade50 : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: complaints > 0 ? Colors.red.shade200 : MMColors.sage, width: 0.8),
                    ),
                    elevation: 0,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: complaints > 0 ? Colors.red.shade100 : MMColors.sage,
                        child: Icon(Icons.warning_amber_outlined,
                            color: complaints > 0 ? Colors.red : MMColors.primaryGreen),
                      ),
                      title: Text('Active Complaints & Appeals: $complaints',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Mediate between customer and artisan on dispute requests'),
                      trailing: const Icon(Icons.chevron_right, color: MMColors.primaryGreen),
                      onTap: onOpenSupport,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _adminMetric(String label, String value, IconData icon) {
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
            Icon(icon, size: 20, color: MMColors.primaryGreen),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: MMColors.textSecondary, fontSize: 11)),
            Text(value, style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 2. Entrepreneurs Tab (Queue, Performance, Badges) ----------------
class _AdminEntrepreneursTab extends ConsumerStatefulWidget {
  const _AdminEntrepreneursTab();

  @override
  ConsumerState<_AdminEntrepreneursTab> createState() => _AdminEntrepreneursTabState();
}

class _AdminEntrepreneursTabState extends ConsumerState<_AdminEntrepreneursTab> {
  int _subTab = 0; // 0: Verification Queue, 1: Performance & Badges

  Future<void> _reviewBusiness(String businessId, String action) async {
    String? reason;
    if (action != 'approve') {
      final ctrl = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(action == 'reject' ? 'Rejection Reason *' : 'Request More Information *',
              style: serif(18, color: MMColors.primaryGreen)),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason / Message'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }

    try {
      await ApiClient.dio.post('/admin/verifications/$businessId', data: {
        'action': action,
        'reason': reason ?? '',
      });
      ref.invalidate(adminBusinessesProvider);
      ref.invalidate(adminStatsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Business ${action.replaceAll('_', ' ')} successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  void _showAssignBadgeDialog(Map<String, dynamic> b) {
    String currentBadge = b['badge'] ?? 'Rising Star';
    final id = b['_id']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Assign Badge: ${b['name']}', style: serif(18, color: MMColors.primaryGreen)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('Best Entrepreneur'),
                value: 'Best Entrepreneur',
                groupValue: currentBadge,
                onChanged: (v) => setDialogState(() => currentBadge = v!),
              ),
              RadioListTile<String>(
                title: const Text('Rising Star'),
                value: 'Rising Star',
                groupValue: currentBadge,
                onChanged: (v) => setDialogState(() => currentBadge = v!),
              ),
              RadioListTile<String>(
                title: const Text('Top Rated'),
                value: 'Top Rated',
                groupValue: currentBadge,
                onChanged: (v) => setDialogState(() => currentBadge = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () async {
                try {
                  await ApiClient.dio.post('/admin/entrepreneurs/$id/badge', data: {'badge': currentBadge});
                  ref.invalidate(adminEntrepreneursProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Badge assigned successfully!')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Assign Badge'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verificationsAsync = ref.watch(adminBusinessesProvider('all'));
    final entrepreneursAsync = ref.watch(adminEntrepreneursProvider(''));

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text('Entrepreneurs', style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Queue')),
                    ButtonSegment(value: 1, label: Text('Badges')),
                  ],
                  selected: {_subTab},
                  onSelectionChanged: (s) => setState(() => _subTab = s.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: _subTab == 0
                ? verificationsAsync.when(
                    loading: () => const LoadingView(),
                    error: (e, _) => ErrorView(message: apiError(e)),
                    data: (items) {
                      final pending = items.where((b) {
                        final s = (b['verification'] as Map?)?['status']?.toString();
                        return s == 'pending' || s == 'in_review';
                      }).toList();

                      if (pending.isEmpty) {
                        return const Center(child: Text('No pending applications in the queue.'));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: pending.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final b = pending[i];
                          final id = b['_id']?.toString() ?? '';
                          final owner = (b['owner'] as Map?) ?? {};
                          final docs = ((b['verification'] as Map?)?['documents'] as List?) ?? [];

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
                                      Text(b['name']?.toString() ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                      Chip(
                                        label: Text(
                                          (b['verification']?['status'] ?? 'pending').toString().toUpperCase(),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Owner: ${owner['name'] ?? '-'} • Phone: ${owner['phone'] ?? '-'}',
                                      style: const TextStyle(fontSize: 13, color: MMColors.textSecondary)),
                                  Text('Experience: ${b['yearsOfExperience'] ?? '1 year'}',
                                      style: const TextStyle(fontSize: 13, color: MMColors.textSecondary)),
                                  Text('Submitted Documents: ${docs.length} files',
                                      style: const TextStyle(fontSize: 13, color: MMColors.textSecondary)),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                                        onPressed: () => _reviewBusiness(id, 'approve'),
                                        child: const Text('Approve'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(side: const BorderSide(color: MMColors.primaryGreen)),
                                        onPressed: () => _reviewBusiness(id, 'request_info'),
                                        child: const Text('Request Info', style: TextStyle(color: MMColors.primaryGreen)),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.red),
                                        onPressed: () => _reviewBusiness(id, 'reject'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  )
                : entrepreneursAsync.when(
                    loading: () => const LoadingView(),
                    error: (e, _) => ErrorView(message: apiError(e)),
                    data: (items) {
                      if (items.isEmpty) {
                        return const Center(child: Text('No active entrepreneurs listed.'));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final b = items[i];
                          final badge = b['badge']?.toString() ?? 'None';

                          return Card(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: MMColors.sage, width: 0.8),
                            ),
                            elevation: 0,
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: MMColors.sage,
                                child: Icon(Icons.storefront, color: MMColors.primaryGreen),
                              ),
                              title: Text(b['name']?.toString() ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('Orders: ${b['orderCount'] ?? 12} • Rating: ${b['rating'] ?? 4.8} ★\nBadge: $badge',
                                  style: const TextStyle(fontSize: 12, color: MMColors.textSecondary)),
                              isThreeLine: true,
                              trailing: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  side: const BorderSide(color: MMColors.primaryGreen),
                                ),
                                onPressed: () => _showAssignBadgeDialog(b),
                                child: const Text('Badge', style: TextStyle(color: MMColors.primaryGreen)),
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

// ---------------- 3. Products Tab (Moderation & Categories) ----------------
class _AdminProductsTab extends ConsumerStatefulWidget {
  const _AdminProductsTab();

  @override
  ConsumerState<_AdminProductsTab> createState() => _AdminProductsTabState();
}

class _AdminProductsTabState extends ConsumerState<_AdminProductsTab> {
  int _productSubTab = 0; // 0: All Products / Moderation, 1: Category Management, 2: AI Trends

  void _showModerateDialog(Map<String, dynamic> product) {
    final id = product['_id']?.toString() ?? '';
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MMColors.warmIvory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Moderate Product: ${product['name']}', style: serif(18, color: MMColors.primaryGreen)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose moderation action:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Admin Reason *', hintText: 'Policy violation reason...'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await ApiClient.dio.post('/admin/products/$id/moderate', data: {
                  'action': 'hide',
                  'reason': reasonCtrl.text.trim(),
                });
                ref.invalidate(adminProductsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Hidden')));
              } catch (_) {}
            },
            child: const Text('Hide Product', style: TextStyle(color: Colors.orange)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              try {
                await ApiClient.dio.post('/admin/products/$id/moderate', data: {
                  'action': 'remove',
                  'reason': reasonCtrl.text.trim(),
                });
                ref.invalidate(adminProductsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Removed (Soft-delete)')));
              } catch (_) {}
            },
            child: const Text('Remove Product'),
          ),
        ],
      ),
    );
  }

  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MMColors.warmIvory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Add New Category', style: serif(18, color: MMColors.primaryGreen)),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Category Name *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await ApiClient.dio.post('/admin/categories', data: {'name': nameCtrl.text.trim()});
                ref.invalidate(adminCategoriesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category Added')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(adminProductsProvider('all'));
    final categoriesAsync = ref.watch(adminCategoriesProvider);
    final trendAsync = ref.watch(adminTrendProvider('7days'));

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text('Products & Catalog', style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Products')),
                    ButtonSegment(value: 1, label: Text('Categories')),
                    ButtonSegment(value: 2, label: Text('AI Trends')),
                  ],
                  selected: {_productSubTab},
                  onSelectionChanged: (s) => setState(() => _productSubTab = s.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: _productSubTab == 0
                ? productsAsync.when(
                    loading: () => const LoadingView(),
                    error: (e, _) => ErrorView(message: apiError(e)),
                    data: (items) {
                      if (items.isEmpty) return const Center(child: Text('No products found.'));

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final p = items[i];
                          final images = (p['images'] as List?) ?? [];
                          final first = images.isNotEmpty ? images.first.toString() : null;
                          final modStatus = p['moderation']?['status'] ?? 'active';
                          final reportCount = p['moderation']?['reportCount'] ?? 0;

                          return Card(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: MMColors.sage, width: 0.8),
                            ),
                            elevation: 0,
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(width: 48, height: 48, child: NetImage(first)),
                              ),
                              title: Text(p['name']?.toString() ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                '${rupees(p['price'])} • Store: ${p['business']?['name'] ?? 'Artisan'}\nReports: $reportCount • Status: $modStatus',
                                style: const TextStyle(fontSize: 12, color: MMColors.textSecondary),
                              ),
                              isThreeLine: true,
                              trailing: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: MMColors.primaryGreen),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _showModerateDialog(p),
                                child: const Text('Moderate', style: TextStyle(color: MMColors.primaryGreen)),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  )
                : _productSubTab == 1
                    ? categoriesAsync.when(
                        loading: () => const LoadingView(),
                        error: (e, _) => ErrorView(message: apiError(e)),
                        data: (cats) {
                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                                  icon: const Icon(Icons.add),
                                  label: const Text('+ Add Category'),
                                  onPressed: _showAddCategoryDialog,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...cats.map((c) {
                                final count = c['productCount'] ?? 0;
                                final isActive = c['isActive'] != false;
                                final id = c['_id']?.toString() ?? '';

                                return Card(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(color: MMColors.sage, width: 0.8),
                                  ),
                                  child: ListTile(
                                    title: Text(c['name']?.toString() ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    subtitle: Text('$count Products Attached',
                                        style: const TextStyle(color: MMColors.textSecondary, fontSize: 13)),
                                    trailing: Switch(
                                      activeTrackColor: MMColors.primaryGreen,
                                      value: isActive,
                                      onChanged: (val) async {
                                        try {
                                          await ApiClient.dio.patch('/admin/categories/$id', data: {'isActive': val});
                                          ref.invalidate(adminCategoriesProvider);
                                        } catch (_) {}
                                      },
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      )
                    : trendAsync.when(
                        loading: () => const LoadingView(),
                        error: (e, _) => ErrorView(message: apiError(e)),
                        data: (trends) {
                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Text('AI Trend Analysis (Auto-Calculated)',
                                  style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                              const Text('Score formula = (Orders × 0.6) + (Rating × 0.3) + (Recent Growth × 0.1)',
                                  style: TextStyle(color: MMColors.textSecondary, fontSize: 12)),
                              const SizedBox(height: 14),
                              ...trends.map((t) => Card(
                                    color: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: const BorderSide(color: MMColors.sage, width: 0.8),
                                    ),
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: MMColors.sage,
                                        child: Text('${t['score']}',
                                            style: const TextStyle(
                                                color: MMColors.primaryGreen,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12)),
                                      ),
                                      title: Text(t['name']?.toString() ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.w700)),
                                      subtitle: Text(
                                          'Store: ${t['businessName']} • ${t['orders']} Orders • ${t['rating']} ★',
                                          style: const TextStyle(fontSize: 12, color: MMColors.textSecondary)),
                                      trailing: Chip(
                                        label: Text(t['trendPercent']?.toString() ?? '+24%'),
                                        backgroundColor: Colors.green.shade100,
                                      ),
                                    ),
                                  )),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 4. Support Tab (Unified Tickets & Appeals) ----------------
class _AdminSupportTab extends ConsumerStatefulWidget {
  const _AdminSupportTab();

  @override
  ConsumerState<_AdminSupportTab> createState() => _AdminSupportTabState();
}

class _AdminSupportTabState extends ConsumerState<_AdminSupportTab> {
  String _supportType = 'all'; // all, refund, replacement, general

  void _showTicketResolutionDialog(Map<String, dynamic> ticket) {
    final id = ticket['_id']?.toString() ?? '';
    final notesCtrl = TextEditingController(text: ticket['adminNotes']?.toString() ?? '');
    String status = ticket['status']?.toString() ?? 'open';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Resolve: ${ticket['ticketNumber']}', style: serif(18, color: MMColors.primaryGreen)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Issue Type: ${ticket['issueType']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Customer: ${ticket['customer']?['name'] ?? 'User'} (${ticket['customer']?['phone'] ?? ''})',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Text('Description: ${ticket['description']}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Ticket Status'),
                  items: ['open', 'in_progress', 'resolved', 'closed']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setDialogState(() => status = v ?? 'open'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Admin Resolution Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () async {
                try {
                  await ApiClient.dio.patch('/support/admin/$id', data: {
                    'status': status,
                    'adminNotes': notesCtrl.text.trim(),
                  });
                  ref.invalidate(adminTicketsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ticket updated successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              },
              child: const Text('Save Resolution'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(adminTicketsProvider(_supportType));

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text('Support Center', style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _tab('All Issues', 'all'),
                _tab('Refund Appeals', 'refund'),
                _tab('Replacement Appeals', 'replacement'),
                _tab('General Issues', 'general'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ticketsAsync.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(message: apiError(e)),
              data: (tickets) {
                if (tickets.isEmpty) return const Center(child: Text('No support tickets in this category.'));

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final t = tickets[i];
                    final status = t['status']?.toString() ?? 'open';

                    return Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: MMColors.sage, width: 0.8),
                      ),
                      elevation: 0,
                      child: ListTile(
                        title: Text('${t['ticketNumber']} • ${t['issueType']}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text(
                          'From: ${t['customer']?['name'] ?? 'User'}\n${t['description']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: MMColors.textSecondary),
                        ),
                        isThreeLine: true,
                        trailing: Chip(
                          label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 10)),
                          backgroundColor: status == 'resolved' ? Colors.green.shade100 : MMColors.sage,
                        ),
                        onTap: () => _showTicketResolutionDialog(t),
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

  Widget _tab(String label, String type) {
    final isSelected = _supportType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: MMColors.primaryGreen,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : MMColors.textPrimary,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        onSelected: (_) => setState(() => _supportType = type),
      ),
    );
  }
}

// ---------------- 5. Profile Tab (Activity Logs & Settings) ----------------
class _AdminProfileTab extends ConsumerWidget {
  const _AdminProfileTab();

  void _showActivityLogsDialog(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.read(adminActivityLogsProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: MMColors.warmIvory,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Activity Logs', style: serif(18, color: MMColors.primaryGreen)),
            const SizedBox(height: 12),
            Expanded(
              child: logsAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => const Text('Could not load logs'),
                data: (logs) {
                  if (logs.isEmpty) return const Center(child: Text('No recorded administrative activities yet.'));
                  return ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final l = logs[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.check_circle_outline, color: MMColors.primaryGreen, size: 20),
                        title: Text(l['description']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                        subtitle: Text('By ${l['admin']?['name'] ?? 'Admin'}', style: const TextStyle(fontSize: 11)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: MMColors.sage,
              child: Icon(Icons.security, size: 44, color: MMColors.primaryGreen),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: Text('Administrator', style: serif(22, color: MMColors.primaryGreen))),
          Center(child: Text(auth.email, style: const TextStyle(color: MMColors.textSecondary))),
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
                ListTile(
                  leading: const Icon(Icons.history, color: MMColors.primaryGreen),
                  title: const Text('Activity Logs', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                  onTap: () => _showActivityLogsDialog(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: MMColors.primaryGreen),
                  title: const Text('About App', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Version 1.0.0 • Maneyindha Marukatte'),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Maneyindha Marukatte',
                    applicationVersion: '1.0.0',
                    applicationLegalese: 'Empowering Home-Based Women Entrepreneurs',
                  ),
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
