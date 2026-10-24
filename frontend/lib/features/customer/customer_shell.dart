import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import '../cart/cart_screen.dart';
import '../orders/orders_screen.dart';

/// Customer Shell conforming to Figma specification:
/// Frozen bottom navigation: Home | Cart | My Orders | Profile
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
      backgroundColor: MMColors.warmIvory,
      body: IndexedStack(
        index: _index,
        children: const [
          _CustomerHome(),
          CartScreen(),
          OrdersScreen(),
          _CustomerProfile(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: MMColors.cream,
        indicatorColor: MMColors.sage,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: MMColors.primaryGreen),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag, color: MMColors.primaryGreen),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: MMColors.primaryGreen),
            label: 'My Orders',
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

class _CustomerHome extends ConsumerStatefulWidget {
  const _CustomerHome();

  @override
  ConsumerState<_CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends ConsumerState<_CustomerHome> {
  String? _selectedCategory;

  void _openLocationSheet(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.read(addressesProvider);
    final selectedAddr = ref.read(selectedDeliveryAddressProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: MMColors.warmIvory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select Delivery Location',
                    style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: MMColors.sage,
                child: Icon(Icons.my_location, color: MMColors.primaryGreen, size: 20),
              ),
              title: const Text('Use Current Location',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Enable GPS to detect current address'),
              onTap: () {
                ref.read(selectedDeliveryAddressProvider.notifier).state = {
                  'label': 'Current Location',
                  'line1': 'MG Road, Bangalore',
                  'city': 'Bengaluru',
                  'state': 'Karnataka',
                  'pincode': '560001',
                };
                Navigator.pop(ctx);
              },
            ),
            const Divider(),
            const Text('Saved Addresses',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: MMColors.textSecondary)),
            const SizedBox(height: 6),
            addressesAsync.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
              error: (_, __) => const Text('Could not load saved addresses'),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No saved addresses yet.', style: TextStyle(color: MMColors.textSecondary)),
                  );
                }
                return Column(
                  children: list.map((a) {
                    final isSelected = selectedAddr?['_id'] == a['_id'] ||
                        (selectedAddr == null && a['isDefault'] == true);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        a['label'] == 'Work' || a['label'] == 'Office'
                            ? Icons.business
                            : a['label'] == 'Hostel'
                                ? Icons.apartment
                                : Icons.home,
                        color: isSelected ? MMColors.primaryGreen : MMColors.textSecondary,
                      ),
                      title: Text(a['label'] ?? 'Home',
                          style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                      subtitle: Text('${a['line1']}, ${a['city']} ${a['pincode']}'),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: MMColors.primaryGreen)
                          : null,
                      onTap: () {
                        ref.read(selectedDeliveryAddressProvider.notifier).state = a;
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: MMColors.primaryGreen),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.add, color: MMColors.primaryGreen),
                label: const Text('+ Add New Address',
                    style: TextStyle(color: MMColors.primaryGreen, fontWeight: FontWeight.w700)),
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/addresses');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleWishlist(WidgetRef ref, String productId) async {
    try {
      await ApiClient.dio.post('/wishlist/products', data: {'productId': productId});
      ref.invalidate(wishlistProvider);
    } catch (_) {}
  }

  Future<void> _addToCart(BuildContext context, WidgetRef ref, String productId) async {
    try {
      await ApiClient.dio.post('/cart/items', data: {'productId': productId, 'quantity': 1});
      ref.invalidate(cartProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Added to Cart 🛍️'),
            duration: Duration(seconds: 2),
          ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final businesses = ref.watch(businessesProvider);
    final products = ref.watch(productsProvider(null));
    final wishlist = ref.watch(wishlistProvider);
    final notifications = ref.watch(notificationsProvider);
    final selectedLocation = ref.watch(selectedDeliveryAddressProvider);

    final wishlistCount = wishlist.maybeWhen(
      data: (d) => (d['products'] as List?)?.length ?? 0,
      orElse: () => 0,
    );

    final unreadNotifs = notifications.maybeWhen(
      data: (d) => (d['unreadCount'] ?? 0) as int,
      orElse: () => 0,
    );

    final wishlistProductIds = wishlist.maybeWhen(
      data: (d) => ((d['products'] as List?) ?? [])
          .map((p) => (p is Map ? p['_id'] : p).toString())
          .toSet(),
      orElse: () => <String>{},
    );

    final customerFirstName = auth.name.isNotEmpty ? auth.name.split(' ').first : 'Customer';

    return SafeArea(
      child: RefreshIndicator(
        color: MMColors.primaryGreen,
        onRefresh: () async {
          ref.invalidate(businessesProvider);
          ref.invalidate(productsProvider);
          ref.invalidate(wishlistProvider);
          ref.invalidate(notificationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Top Header: Welcome, Location Selector & Action Icons
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome, $customerFirstName',
                          style: serif(22, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: () => _openLocationSheet(context, ref),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, size: 16, color: MMColors.primaryGreen),
                            const SizedBox(width: 4),
                            Text(
                              selectedLocation?['label'] != null
                                  ? '${selectedLocation!['label']} (${selectedLocation['city'] ?? ''})'
                                  : 'Delivery Location',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: MMColors.textPrimary),
                            ),
                            const Icon(Icons.arrow_drop_down, color: MMColors.primaryGreen, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Wishlist Icon
                IconButton(
                  tooltip: 'Wishlist',
                  icon: Badge(
                    isLabelVisible: wishlistCount > 0,
                    label: Text('$wishlistCount'),
                    backgroundColor: MMColors.primaryGreen,
                    child: const Icon(Icons.favorite_border, color: MMColors.primaryGreen, size: 24),
                  ),
                  onPressed: () => context.push('/wishlist'),
                ),
                // Notifications Icon
                IconButton(
                  tooltip: 'Notifications',
                  icon: Badge(
                    isLabelVisible: unreadNotifs > 0,
                    label: Text('$unreadNotifs'),
                    backgroundColor: Colors.orange,
                    child: const Icon(Icons.notifications_none, color: MMColors.primaryGreen, size: 24),
                  ),
                  onPressed: () => context.push('/notifications'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar
            GestureDetector(
              onTap: () => context.push('/search'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MMColors.sage, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, color: MMColors.primaryGreen),
                    SizedBox(width: 12),
                    Text(
                      'Search Products, Stores or Categories...',
                      style: TextStyle(color: MMColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Categories
            Text('Categories', style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
            const SizedBox(height: 10),
            businesses.when(
              loading: () => const SizedBox(height: 90, child: LoadingView()),
              error: (e, _) => const SizedBox(),
              data: (shops) {
                final catMap = <String, String?>{
                  'Baking': 'https://images.pexels.com/photos/1055272/pexels-photo-1055272.jpeg?auto=compress&cs=tinysrgb&w=400',
                  'Handicrafts': 'https://images.pexels.com/photos/260024/pexels-photo-260024.jpeg?auto=compress&cs=tinysrgb&w=400',
                  'Tiffin & Meals': 'https://images.pexels.com/photos/1624487/pexels-photo-1624487.jpeg?auto=compress&cs=tinysrgb&w=400',
                  'Tailoring': 'https://images.pexels.com/photos/3738088/pexels-photo-3738088.jpeg?auto=compress&cs=tinysrgb&w=400',
                  'Home Decor': 'https://images.pexels.com/photos/1090638/pexels-photo-1090638.jpeg?auto=compress&cs=tinysrgb&w=400',
                };

                for (final b in shops) {
                  final c = b['category'];
                  if (c is Map && c['name'] != null && b['bannerUrl'] != null) {
                    catMap[c['name'].toString()] = b['bannerUrl'].toString();
                  }
                }

                final catList = catMap.keys.toList();

                return SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: catList.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) {
                      final name = catList[i];
                      final isSelected = _selectedCategory == name;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = isSelected ? null : name),
                        child: Column(
                          children: [
                            Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? MMColors.primaryGreen : MMColors.sage,
                                  width: isSelected ? 3 : 1.5,
                                ),
                              ),
                              child: ClipOval(
                                child: NetImage(catMap[name], width: 66, height: 66),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? MMColors.primaryGreen : MMColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // Popular Products Section (Frozen spec: horizontal scroll, no "View All" button)
            Text('Popular Products',
                style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            products.when(
              loading: () => const SizedBox(height: 260, child: LoadingView()),
              error: (e, _) => ErrorView(
                message: 'Could not load popular products.',
                onRetry: () => ref.invalidate(productsProvider),
              ),
              data: (items) {
                var list = List<Map<String, dynamic>>.from(items);
                if (_selectedCategory != null) {
                  list = list.where((p) {
                    final cat = p['category'] is Map ? p['category']['name'] : '';
                    return cat == _selectedCategory;
                  }).toList();
                }

                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No Products Available Yet\nProducts from local entrepreneurs will appear here soon.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MMColors.textSecondary, fontSize: 14)),
                    ),
                  );
                }

                return SizedBox(
                  height: 275,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (ctx, i) {
                      final p = list[i];
                      final pId = p['_id']?.toString() ?? '';
                      final images = (p['images'] as List?) ?? [];
                      final firstImg = images.isNotEmpty ? images.first.toString() : null;
                      final rating = (p['rating'] is Map) ? (p['rating']['avg'] ?? 4.8) : 4.8;
                      final storeName = (p['business'] is Map)
                          ? p['business']['name']?.toString() ?? 'Artisan Store'
                          : 'Artisan Store';
                      final inWishlist = wishlistProductIds.contains(pId);

                      return SizedBox(
                        width: 190,
                        child: Card(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: MMColors.sage, width: 0.8),
                          ),
                          elevation: 0,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => context.push('/product/$pId'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    SizedBox(
                                      height: 125,
                                      width: double.infinity,
                                      child: NetImage(firstImg),
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Material(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        shape: const CircleBorder(),
                                        child: IconButton(
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(5),
                                          icon: Icon(
                                            inWishlist ? Icons.favorite : Icons.favorite_border,
                                            color: inWishlist ? Colors.red : MMColors.primaryGreen,
                                            size: 18,
                                          ),
                                          onPressed: () => _toggleWishlist(ref, pId),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p['name']?.toString() ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        rupees(p['price']),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: MMColors.primaryGreen),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.star, size: 13, color: MMColors.accentGold),
                                          const SizedBox(width: 3),
                                          Text('$rating', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              storeName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11, color: MMColors.textSecondary),
                                            ),
                                          ),
                                          const Icon(Icons.verified, size: 13, color: MMColors.primaryGreen),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 32,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: MMColors.primaryGreen,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () => _addToCart(context, ref, pId),
                                          child: const Text('Add to Cart',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Verified Entrepreneur Stores
            Text('Verified Entrepreneur Stores',
                style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            businesses.when(
              loading: () => const SizedBox(height: 160, child: LoadingView()),
              error: (e, _) => const SizedBox(),
              data: (shops) {
                return SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: shops.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) {
                      final s = shops[i];
                      return SizedBox(
                        width: 220,
                        child: Card(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: MMColors.sage, width: 0.8),
                          ),
                          elevation: 0,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => context.push('/business/${s['_id']}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 90, width: double.infinity, child: NetImage(s['bannerUrl']?.toString())),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(s['name']?.toString() ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: serif(14, weight: FontWeight.w700)),
                                          ),
                                          const Icon(Icons.verified, size: 15, color: MMColors.primaryGreen),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        s['address']?['city']?.toString() ?? 'Bengaluru',
                                        style: const TextStyle(fontSize: 12, color: MMColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CustomerProfile extends ConsumerWidget {
  const _CustomerProfile();

  void _showHelpSupport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MMColors.warmIvory,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Help & Support', style: serif(20, color: MMColors.primaryGreen)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: MMColors.sage,
                child: Icon(Icons.smart_toy, color: MMColors.primaryGreen),
              ),
              title: const Text('Ask Maneyinda AI', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Get quick guidance on orders, deliveries & features'),
              onTap: () {
                Navigator.pop(ctx);
                _showAiGuide(context);
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: MMColors.sage,
                child: Icon(Icons.confirmation_number_outlined, color: MMColors.primaryGreen),
              ),
              title: const Text('Raise Support Ticket', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Report an issue with account, order, or refund'),
              onTap: () {
                Navigator.pop(ctx);
                _showRaiseTicketDialog(context, ref);
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: MMColors.sage,
                child: Icon(Icons.history, color: MMColors.primaryGreen),
              ),
              title: const Text('My Support Tickets', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Track status of your submitted tickets'),
              onTap: () {
                Navigator.pop(ctx);
                _showMyTicketsDialog(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAiGuide(BuildContext context) {
    final questions = [
      'How do I place an order?',
      'How does delivery work?',
      'What is the One Entrepreneur Per Order rule?',
      'How do I request a refund or return?',
      'How do I become an entrepreneur?',
    ];

    final answers = [
      'Browse products from our home artisans, tap Add to Cart, and proceed to Checkout. Orders are prepared fresh by local home-based women entrepreneurs!',
      'Entrepreneurs offer Home Delivery within their delivery radius (typically 5-10 km) or Self-Pickup directly from their home kitchen or studio.',
      'To ensure quality and direct artisanal care, each order is made with a single entrepreneur. You can have items from multiple stores in your cart and order them separately.',
      'Delivered orders with return/refund policies enabled allow you to request a refund or replacement within the support window from your My Orders screen.',
      'Go to your Profile tab and tap "Become an Entrepreneur". Submit your business information and verification documents for quick admin approval!',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: MMColors.warmIvory,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          int? selectedQ;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: MMColors.primaryGreen,
                      child: Icon(Icons.smart_toy, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Maneyinda AI Guide', style: serif(18, color: MMColors.primaryGreen)),
                        const Text('App Guidance & Answers', style: TextStyle(fontSize: 12, color: MMColors.textSecondary)),
                      ],
                    ),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Frequently Asked Questions:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                ...List.generate(questions.length, (i) {
                  return Card(
                    color: selectedQ == i ? MMColors.cream : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: MMColors.sage, width: 0.8),
                    ),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      key: Key('$i-${selectedQ == i}'),
                      initiallyExpanded: selectedQ == i,
                      onExpansionChanged: (expanded) => setModalState(() => selectedQ = expanded ? i : null),
                      title: Text(questions[i], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(answers[i],
                              style: const TextStyle(fontSize: 13, color: MMColors.textPrimary, height: 1.4)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRaiseTicketDialog(BuildContext context, WidgetRef ref) {
    String selectedType = 'Order Issue';
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Raise Support Ticket', style: serif(18, color: MMColors.primaryGreen)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Issue Type'),
                items: [
                  'Account Issue',
                  'Payment Issue',
                  'Order Issue',
                  'Refund Appeal',
                  'Replacement Appeal',
                  'Other Issue',
                ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setDialogState(() => selectedType = v ?? 'Order Issue'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'Describe your issue in detail...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () async {
                if (descCtrl.text.trim().isEmpty) return;
                try {
                  await ApiClient.dio.post('/support', data: {
                    'issueType': selectedType,
                    'description': descCtrl.text.trim(),
                  });
                  ref.invalidate(supportTicketsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Support ticket raised successfully!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Submit Ticket'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMyTicketsDialog(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.read(supportTicketsProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: MMColors.warmIvory,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Support Tickets', style: serif(18, color: MMColors.primaryGreen)),
            const SizedBox(height: 12),
            Expanded(
              child: ticketsAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => const Text('Could not load tickets'),
                data: (tickets) {
                  if (tickets.isEmpty) {
                    return const Center(child: Text('No support tickets submitted yet.'));
                  }
                  return ListView.builder(
                    itemCount: tickets.length,
                    itemBuilder: (_, i) {
                      final t = tickets[i];
                      final status = t['status']?.toString() ?? 'open';
                      return Card(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: MMColors.sage, width: 0.8),
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('${t['ticketNumber']} • ${t['issueType']}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(t['description']?.toString() ?? '', maxLines: 2),
                          trailing: Chip(
                            label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 10)),
                            backgroundColor: status == 'resolved' ? Colors.green.shade100 : MMColors.sage,
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
      ),
    );
  }

  void _showSwitchRoleDialog(BuildContext context, WidgetRef ref) {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MMColors.warmIvory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Switch to Entrepreneur', style: serif(18, color: MMColors.primaryGreen)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your entrepreneur credentials to access your store:'),
            const SizedBox(height: 12),
            TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Username or Email')),
            const SizedBox(height: 10),
            TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
            onPressed: () async {
              try {
                await ref.read(authProvider.notifier).login(userCtrl.text.trim(), passCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) context.go('/seller');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              }
            },
            child: const Text('Login & Switch'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MMColors.warmIvory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout Confirmation'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
              context.go('/');
            },
            child: const Text('Logout'),
          ),
        ],
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
          const SizedBox(height: 12),
          Center(child: Text(auth.name, style: serif(22, color: MMColors.primaryGreen))),
          Center(
            child: Text(auth.email, style: const TextStyle(color: MMColors.textSecondary, fontSize: 13)),
          ),
          const SizedBox(height: 24),
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
                  leading: const Icon(Icons.location_on_outlined, color: MMColors.primaryGreen),
                  title: const Text('Address Book', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                  onTap: () => context.push('/addresses'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_none, color: MMColors.primaryGreen),
                  title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                  onTap: () => context.push('/notifications'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined, color: MMColors.primaryGreen),
                  title: const Text('Help & Support', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                  onTap: () => _showHelpSupport(context, ref),
                ),
                const Divider(height: 1),
                if (!auth.isEntrepreneur)
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined, color: MMColors.primaryGreen),
                    title: const Text('Become an Entrepreneur', style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                    onTap: () => context.push('/seller/onboarding/business'),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.swap_horiz, color: MMColors.primaryGreen),
                    title: const Text('Switch to Entrepreneur', style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                    onTap: () => _showSwitchRoleDialog(context, ref),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                  trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                  onTap: () => _showLogoutDialog(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
