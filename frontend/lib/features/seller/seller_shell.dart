import '../../shared/user_avatar.dart';
import 'package:flutter/material.dart';
import '../../l10n/language_picker.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:image_picker/image_picker.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import 'promo_video_manager.dart';
import 'shop_photo_manager.dart';
import 'suspension_banner.dart';
import '../notifications/notifications_screen.dart';
import 'seller_order_card.dart';
import 'seller_badges.dart';

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
    // A shop can sell only after an administrator has approved its submitted documents.
    final mine = ref.watch(myBusinessesProvider).valueOrNull;
    if (mine != null && mine.isNotEmpty) {
      final v = (mine.first['verification'] as Map?) ?? const {};
      final status = v['status']?.toString() ?? 'pending';
      if (status != 'approved') {
        return _ApprovalGate(
          shop: mine.first,
          shopName: mine.first['name']?.toString() ?? 'Your shop',
          status: status,
          reason: v['rejectionReason']?.toString(),
        );
      }
    }
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
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: context.tr('Dashboard')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2), label: context.tr('Products')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: context.tr('Orders')),
          NavigationDestination(icon: const Icon(Icons.show_chart), label: context.tr('Earnings')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.tr('Profile')),
        ],
      ),
    );
  }
}

/// Shown instead of the seller tools until the administrator approves the application.
class _ApprovalGate extends ConsumerWidget {
  final String shopName;
  final String status; // pending (not submitted) | in_review | rejected
  final String? reason;
  final Map<String, dynamic> shop;
  const _ApprovalGate({required this.shop, required this.shopName, required this.status, this.reason});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = status == 'in_review';
    final rejected = status == 'rejected';
    final title = waiting
        ? 'Waiting for approval'
        : rejected
            ? 'Application not approved'
            : 'Finish your application';
    final body = waiting
        ? 'Thank you! Our team is checking the documents for $shopName. '
            'You can start selling as soon as it is approved. We will notify you here.'
        : rejected
            ? 'Your application for $shopName was not approved.'
                '${(reason ?? '').isNotEmpty ? '\n\nReason: $reason' : ''}'
                '\n\nYou can fix the documents and submit again.'
            : 'Upload your ID proof and business proof and submit them for review. '
                'Your shop goes live only after an administrator approves it.';
    return Scaffold(
      backgroundColor: MMColors.olive,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: MMColors.cream,
                  child: Icon(
                    waiting ? Icons.hourglass_top : (rejected ? Icons.error_outline : Icons.description_outlined),
                    size: 44, color: MMColors.deepOlive,
                  ),
                ),
                const SizedBox(height: 20),
                Text(title, style: serif(24, color: MMColors.cream), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(body,
                    textAlign: TextAlign.center,
                    style: serif(15, weight: FontWeight.w400, color: MMColors.cream)),
                const SizedBox(height: 28),
                if (!waiting)
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: MMColors.cream, foregroundColor: MMColors.deepOlive),
                    onPressed: () {
                      // The documents step reads the shop from this onboarding state.
                      ref.read(sellerOnboardingProvider.notifier).state = {
                        'businessId': shop['_id'],
                        'businessName': shop['name'],
                        'address': (shop['address'] as Map?)?['line1'],
                      };
                      context.go('/seller/onboarding/documents');
                    },
                    child: Text(rejected ? 'Update documents' : 'Upload documents'),
                  ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: MMColors.cream),
                  onPressed: () => ref.invalidate(myBusinessesProvider),
                  child: const Text('Refresh status'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: MMColors.cream),
                  onPressed: () async {
                    await ref.read(authProvider.notifier).switchRole('customer');
                    ref.invalidate(ordersProvider);
                    ref.invalidate(receivedOrdersProvider);
                    ref.invalidate(cartProvider);
                    if (context.mounted) context.go('/app');
                  },
                  child: const Text('Browse as a customer'),
                ),
              ]),
            ),
          ),
        ),
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
    final orders = ref.watch(receivedOrdersProvider);

    return Container(
      color: MMColors.olive,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            UserAvatar(
              url: auth.user?['avatarUrl']?.toString(),
              name: auth.name,
              radius: 26,
              backgroundColor: MMColors.cream,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${context.tr('Welcome')},\n${auth.name}',
                  style: serif(20, color: MMColors.cream)),
            ),
            const NotificationBell(color: MMColors.cream),
          ]),
          const SizedBox(height: 20),
          const SellerBadgesCard(),
          const OrdersAutoRefresh(),
          const SuspensionBanner(),
          const ShopPhotoNudge(),
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
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.7,
                children: [
                  _StatCard(label: context.tr('Total Orders'), value: '${received.length}'),
                  _StatCard(label: context.tr('Total Earnings'), value: rupees(_earnings(received))),
                  _StatCard(label: context.tr('Total Products'),
                      value: '${products.asData?.value.length ?? 0}'),
                  _StatCard(label: context.tr('Average Rating'),
                      value: (rating['count'] ?? 0) == 0 ? 'New' : '${rating['avg']} ★'),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(context.tr('Recent Orders'), style: serif(18, color: MMColors.cream)),
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
  /// Opens the phone/computer gallery, checks size, uploads to the server and returns the photo URL.
  Future<String?> _pickGalleryPhoto() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return null; // cancelled
    final bytes = await picked.readAsBytes();
    if (bytes.length > 3 * 1024 * 1024) {
      throw 'Please choose an image under 3 MB.';
    }
    final form = FormData.fromMap({'photo': MultipartFile.fromBytes(bytes, filename: picked.name)});
    final res = await ApiClient.dio.post('/products/photo', data: form);
    return (res.data['data'] as Map)['url'].toString();
  }

  Future<void> _addProduct(String businessId) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final stock = TextEditingController(text: '10');
    final description = TextEditingController();
    String? imageUrl;
    bool aiBusy = false;
    String? aiNote;
    bool photoBusy = false;
    String? photoNote;

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
                    onChanged: (_) => setD(() {}),
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 10),
                TextField(controller: price, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price (₹)')),
                const SizedBox(height: 10),
                TextField(controller: stock, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stock')),
                const SizedBox(height: 10),
                TextField(controller: description, maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description')),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: aiBusy
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Write with AI'),
                    onPressed: (aiBusy || name.text.trim().length < 2)
                        ? null
                        : () async {
                            setD(() { aiBusy = true; aiNote = null; });
                            try {
                              final res = await ApiClient.dio.post('/ai/product-description', data: {
                                'name': name.text.trim(),
                                if (description.text.trim().isNotEmpty)
                                  'details': description.text.trim(),
                              });
                              description.text = res.data['data']['description'].toString();
                              if (ctx2.mounted) setD(() => aiNote = 'AI draft added — please review and edit before saving.');
                            } catch (e) {
                              if (ctx2.mounted) setD(() => aiNote = apiError(e));
                            } finally {
                              if (ctx2.mounted) setD(() => aiBusy = false);
                            }
                          },
                  ),
                ),
                if (aiNote != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(aiNote!, style: Theme.of(ctx2).textTheme.bodySmall),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(imageUrl == null ? 'Product photo:' : 'Photo selected ✓'),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: photoBusy
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(photoBusy ? 'Uploading…' : 'Choose from gallery'),
                    onPressed: photoBusy
                        ? null
                        : () async {
                            setD(() { photoBusy = true; photoNote = null; });
                            try {
                              final url = await _pickGalleryPhoto();
                              if (url != null && ctx2.mounted) setD(() => imageUrl = url);
                            } catch (e) {
                              if (ctx2.mounted) setD(() => photoNote = apiError(e));
                            } finally {
                              if (ctx2.mounted) setD(() => photoBusy = false);
                            }
                          },
                  ),
                ),
                if (photoNote != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(photoNote!, style: Theme.of(ctx2).textTheme.bodySmall),
                  ),
                if (imageUrl != null && !imageUrl!.contains('pexels'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(imageUrl!, height: 90, fit: BoxFit.cover),
                    ),
                  ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Or pick a suggestion:'),
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
              title: Text(context.tr('My Products'), style: serif(20)),
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
      ref.invalidate(receivedOrdersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(receivedOrdersProvider);
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
        const OrdersAutoRefresh(),
        ListTile(title: Text(context.tr('Orders Received'), style: serif(20))),
        Expanded(
          child: orders.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
                message: apiError(e), onRetry: () => ref.invalidate(receivedOrdersProvider)),
            data: (items) => items.isEmpty
                ? const EmptyView(message: 'No orders yet.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final o = items[i];
                      final status = o['status'].toString();
                      final pickup = o['isSelfPickup'] == true;
                      // Self-pickup orders skip the delivery run: ready -> collected.
                      final next = pickup
                          ? (status == 'ready' ? 'delivered' : (status == 'picked_up' || status == 'out_for_delivery') ? null : nextStep[status])
                          : nextStep[status];
                      return SellerOrderCard(
                        order: o,
                        next: next,
                        onAdvance: (n) => _transition(context, ref, o['_id'].toString(), n),
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
    final orders = ref.watch(receivedOrdersProvider);
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
              _StatCard(label: context.tr('Today'),
                  value: rupees(_earnings(items, window: const Duration(days: 1)))),
              _StatCard(label: context.tr('This Week'),
                  value: rupees(_earnings(items, window: const Duration(days: 7)))),
              _StatCard(label: context.tr('This Month'),
                  value: rupees(_earnings(items, window: const Duration(days: 30)))),
              _StatCard(label: context.tr('All Time'), value: rupees(_earnings(items))),
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
const _maxPhotoBytes = 2 * 1024 * 1024;

void _toast(BuildContext context, String m) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

/// Optional profile photo. The server re-validates type, size and who is asking.
Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
  try {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (picked == null) return; // cancelled
    final bytes = await picked.readAsBytes();
    if (bytes.length > _maxPhotoBytes) {
      if (context.mounted) _toast(context, 'Please choose an image under 2 MB.');
      return;
    }
    await ref.read(authProvider.notifier).uploadAvatar(bytes, picked.name);
    if (context.mounted) _toast(context, 'Profile photo updated.');
  } catch (e) {
    if (context.mounted) _toast(context, apiError(e));
  }
}

Future<void> _removePhoto(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authProvider.notifier).removeAvatar();
    if (context.mounted) _toast(context, 'Profile photo removed.');
  } catch (e) {
    if (context.mounted) _toast(context, apiError(e));
  }
}

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
          Center(child: UserAvatar(
            url: auth.user?['avatarUrl']?.toString(),
            name: auth.name,
            radius: 44,
            backgroundColor: MMColors.cream,
          )),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: MMColors.cream),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(auth.user?['avatarUrl'] == null ? 'Add photo (optional)' : 'Change photo'),
              onPressed: () => _changePhoto(context, ref),
            ),
            if (auth.user?['avatarUrl'] != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: MMColors.cream),
                onPressed: () => _removePhoto(context, ref),
                child: const Text('Remove'),
              ),
          ]),
          const SizedBox(height: 12),
          Center(child: Text(auth.name, style: serif(22, color: MMColors.cream))),
          Center(child: Text(auth.email,
              style: serif(14, weight: FontWeight.w400, color: MMColors.cream))),
          const SizedBox(height: 20),
          Card(color: MMColors.cream, child: Column(children: [
            ListTile(
              title: Text(context.tr('Business Profile')),
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
              title: Text(context.tr('Shop photo')),
              subtitle: Text(context.tr('The picture customers see on the home screen')),
              trailing: const Icon(Icons.chevron_right),
              onTap: shops.asData?.value.isNotEmpty == true
                  ? () => showShopPhotoSheet(context, shops.asData!.value.first)
                  : null,
            ),
            ListTile(
              title: Text(context.tr('Shop video')),
              subtitle: const Text('Show customers how you make your products'),
              trailing: const Icon(Icons.chevron_right),
              onTap: shops.asData?.value.isNotEmpty == true
                  ? () => showPromoVideoSheet(context, shops.asData!.value.first)
                  : null,
            ),
            ListTile(
              title: Text(context.tr('Bank Details')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _bankDetails(context, ref),
            ),
            ListTile(
              title: Text(context.tr('Address')),
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
              title: Text(context.tr('Change Password')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changePassword(context, ref),
            ),
            ListTile(
              title: Text(context.tr('Become a customer')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await ref.read(authProvider.notifier).switchRole('customer');
                ref.invalidate(ordersProvider);
                ref.invalidate(receivedOrdersProvider);
                ref.invalidate(cartProvider);
                if (context.mounted) context.go('/app');
              },
            ),
            ListTile(
              title: Text(context.tr('Reviews')),
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
            const LanguageTile(),
            ListTile(
              title: Text(context.tr('Logout')),
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
