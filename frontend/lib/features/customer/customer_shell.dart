import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import '../cart/cart_screen.dart';
import '../orders/orders_screen.dart';

/// Main Customer shell with responsive web & mobile layouts.
class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key});
  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);
    final cart = ref.watch(cartProvider);
    final cartCount = ((cart.asData?.value['items'] as List?) ?? []).length;

    return Scaffold(
      appBar: isDesktop
          ? PreferredSize(
              preferredSize: const Size.fromHeight(68),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: MMColors.borderLight)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _index = 0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: MMColors.cream,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.storefront_rounded,
                                color: MMColors.deepOlive, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Text('Maneyindha Marukatte',
                              style: serif(20, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _navButton(0, 'Marketplace', Icons.home_rounded),
                    const SizedBox(width: 8),
                    _navButton(1, 'My Orders', Icons.receipt_long_rounded),
                    const SizedBox(width: 8),
                    _navButton(2, 'Cart', Icons.shopping_bag_rounded, badge: cartCount),
                    const SizedBox(width: 8),
                    _navButton(3, 'Profile', Icons.person_rounded),
                  ],
                ),
              ),
            )
          : null,
      body: IndexedStack(index: _index, children: const [
        _CustomerHome(),
        OrdersScreen(),
        CartScreen(),
        _CustomerProfile(),
      ]),
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Orders',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: cartCount > 0,
                    label: Text('$cartCount'),
                    backgroundColor: MMColors.terracotta,
                    child: const Icon(Icons.shopping_bag_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: cartCount > 0,
                    label: Text('$cartCount'),
                    backgroundColor: MMColors.terracotta,
                    child: const Icon(Icons.shopping_bag),
                  ),
                  label: 'Cart',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
    );
  }

  Widget _navButton(int index, String label, IconData icon, {int badge = 0}) {
    final isSelected = _index == index;
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: isSelected ? MMColors.deepOlive : MMColors.textSecondary,
        backgroundColor: isSelected ? MMColors.sageLight : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => setState(() => _index = index),
      icon: Badge(
        isLabelVisible: badge > 0,
        label: Text('$badge'),
        backgroundColor: MMColors.terracotta,
        child: Icon(icon, size: 20),
      ),
      label: Text(label, style: sans(14, weight: isSelected ? FontWeight.w700 : FontWeight.w500)),
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
  final _searchController = TextEditingController();

  static const List<Map<String, dynamic>> _presetCategories = [
    {'name': 'All', 'icon': Icons.grid_view_rounded},
    {'name': 'Baking', 'icon': Icons.cake_outlined},
    {'name': 'Handicrafts', 'icon': Icons.palette_outlined},
    {'name': 'Tiffin Center', 'icon': Icons.lunch_dining_outlined},
    {'name': 'Tailoring', 'icon': Icons.content_cut_outlined},
    {'name': 'Boutique', 'icon': Icons.checkroom_outlined},
  ];

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final businesses = ref.watch(businessesProvider);
    final products = ref.watch(productsProvider(null));

    final firstName = auth.isLoggedIn && auth.name.isNotEmpty
        ? auth.name.split(' ').first
        : 'Neighbor';

    return SafeArea(
      child: RefreshIndicator(
        color: MMColors.deepOlive,
        onRefresh: () async {
          ref.invalidate(businessesProvider);
          ref.invalidate(productsProvider(null));
        },
        child: ResponsiveContainer(
          maxWidth: 1200,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ListView(
            children: [
              // Welcome Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Namaste, $firstName 🌸', style: serif(26, weight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'Handcrafted delicacies & artisanal treasures from women entrepreneurs nearby',
                          style: sans(14, color: MMColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      if (!auth.isLoggedIn) {
                        context.push('/login');
                      }
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: MMColors.sage,
                      backgroundImage: (auth.user?['avatarUrl'] != null)
                          ? NetworkImage(auth.user!['avatarUrl'].toString())
                          : null,
                      child: auth.user?['avatarUrl'] == null
                          ? const Icon(Icons.person, color: MMColors.deepOlive)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Search Bar
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 22, color: MMColors.textMuted),
                  hintText: 'Search homemade cakes, pickles, tailoring, pottery…',
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 24),

              // Categories Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Categories', style: serif(20, weight: FontWeight.w700)),
                  if (_category != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => setState(() => _category = null),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Clear Filter'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _presetCategories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final item = _presetCategories[i];
                    final catName = item['name'] as String;
                    final isAll = catName == 'All';
                    final isSelected = isAll ? (_category == null) : (_category == catName);

                    return ChoiceChip(
                      selected: isSelected,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item['icon'] as IconData, size: 16),
                          const SizedBox(width: 6),
                          Text(catName),
                        ],
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _category = isAll ? null : (selected ? catName : null);
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // Nearby Shops Carousel
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Nearby Women Entrepreneurs', style: serif(20, weight: FontWeight.w700)),
                  Text(
                    'Verified Sellers',
                    style: sans(12, weight: FontWeight.w600, color: MMColors.olive),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 195,
                child: businesses.when(
                  loading: () => ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 4,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, __) => const SizedBox(
                      width: 240,
                      child: ProductCardSkeleton(),
                    ),
                  ),
                  error: (e, _) => ErrorView(
                    message: 'Could not load shops.',
                    onRetry: () => ref.invalidate(businessesProvider),
                  ),
                  data: (shops) {
                    final filtered = shops.where((b) {
                      if (_category == null) return true;
                      final c = b['category'];
                      final catName = c is Map ? c['name']?.toString() : c?.toString();
                      return catName?.toLowerCase() == _category!.toLowerCase();
                    }).toList();

                    if (filtered.isEmpty) {
                      return Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _category != null
                                  ? 'No shops registered under "$_category" yet.'
                                  : 'No verified shops found.',
                              style: sans(14, color: MMColors.textSecondary),
                            ),
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (_, i) => _ShopCard(business: filtered[i]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),

              // Popular Products Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _category != null ? 'Products in "$_category"' : 'Handcrafted & Homemade Treasures',
                    style: serif(20, weight: FontWeight.w700),
                  ),
                  if (products.asData != null)
                    Text(
                      '${products.asData!.value.length} items',
                      style: sans(13, color: MMColors.textMuted),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              products.when(
                loading: () => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Breakpoints.gridColumns(context),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: 6,
                  itemBuilder: (_, __) => const ProductCardSkeleton(),
                ),
                error: (e, _) => ErrorView(
                  message: 'Could not load products.',
                  onRetry: () => ref.invalidate(productsProvider(null)),
                ),
                data: (items) {
                  var list = List<Map<String, dynamic>>.from(items);

                  // Filter by selected category (FIXES THE BUG FROM PHASE 1 AUDIT)
                  if (_category != null) {
                    list = list.where((p) {
                      final c = p['category'];
                      final catName = c is Map ? c['name']?.toString() : c?.toString();
                      final desc = p['description']?.toString() ?? '';
                      final pName = p['name']?.toString() ?? '';
                      return (catName != null &&
                              catName.toLowerCase() == _category!.toLowerCase()) ||
                          pName.toLowerCase().contains(_category!.toLowerCase()) ||
                          desc.toLowerCase().contains(_category!.toLowerCase());
                    }).toList();
                  }

                  // Filter by search query
                  if (_query.isNotEmpty) {
                    list = list.where((p) {
                      final name = p['name']?.toString().toLowerCase() ?? '';
                      final desc = p['description']?.toString().toLowerCase() ?? '';
                      return name.contains(_query) || desc.contains(_query);
                    }).toList();
                  }

                  // Sort by popularity / rating
                  list.sort((a, b) {
                    final ra = ((a['rating'] as Map?)?['count'] ?? 0) as num;
                    final rb = ((b['rating'] as Map?)?['count'] ?? 0) as num;
                    return rb.compareTo(ra);
                  });

                  if (list.isEmpty) {
                    return EmptyView(
                      message: _query.isNotEmpty
                          ? 'No products found for "$_query"'
                          : 'No products in this category yet',
                      subtitle: 'Try clearing your filters or search for another item.',
                      icon: Icons.search_off_rounded,
                      buttonLabel: (_query.isNotEmpty || _category != null) ? 'Reset Filters' : null,
                      onButtonPressed: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _category = null;
                        });
                      },
                    );
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Breakpoints.gridColumns(context),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => ProductCard(product: list[i]),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
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
    final cat = business['category'];
    final catName = cat is Map ? cat['name']?.toString() : cat?.toString();

    return SizedBox(
      width: 240,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/business/${business['_id']}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 105,
                width: double.infinity,
                child: NetImage(business['bannerUrl']?.toString()),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            business['name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: serif(15, weight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 16, color: MMColors.deepOlive),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (catName != null) ...[
                      Text(
                        catName,
                        style: sans(12, color: MMColors.textMuted, weight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RatingBadge(rating: rating),
                        Text(
                          'Nearby',
                          style: sans(12, color: MMColors.olive, weight: FontWeight.w600),
                        ),
                      ],
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

class _CustomerProfile extends ConsumerWidget {
  const _CustomerProfile();

  Future<void> _editPersonal(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    final name = TextEditingController(text: auth.name);
    final phone = TextEditingController(text: auth.user?['phone']?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Personal Details', style: serif(20, weight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      await ref.read(authProvider.notifier).updateProfile({
        'name': name.text.trim(),
        'phone': phone.text.trim(),
      });
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
        title: Text('Address Book', style: serif(20, weight: FontWeight.w700)),
        content: TextField(
          controller: line,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Delivery Address',
            hintText: 'House / Flat number, Street, Area, Bengaluru',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      await ref.read(authProvider.notifier).updateProfile({
        'addresses': [
          {'label': 'Home', 'line1': line.text.trim()}
        ],
      });
    }
  }

  void _showWishlist(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MMColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Consumer(
          builder: (_, ref2, __) {
            final wishlist = ref2.watch(wishlistProvider);
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: MMColors.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('My Wishlist & Favorites', style: serif(22, weight: FontWeight.w700)),
                const SizedBox(height: 16),
                wishlist.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(
                    message: 'Could not load wishlist.',
                    onRetry: () => ref2.invalidate(wishlistProvider),
                  ),
                  data: (data) {
                    final products = (data['products'] as List?) ?? [];
                    if (products.isEmpty) {
                      return const EmptyView(
                        message: 'Your wishlist is empty',
                        subtitle: 'Heart items in the marketplace to find them here anytime.',
                        icon: Icons.favorite_border_rounded,
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final p = Map<String, dynamic>.from(products[i] as Map);
                        final images = (p['images'] as List?) ?? [];
                        return Card(
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: NetImage(images.isNotEmpty ? images.first.toString() : null),
                              ),
                            ),
                            title: Text(p['name']?.toString() ?? '', style: serif(15)),
                            subtitle: Text(rupees(p['price'])),
                            trailing: IconButton(
                              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.push('/product/${p['_id']}');
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (!auth.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: MMColors.cream,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline, size: 48, color: MMColors.deepOlive),
              ),
              const SizedBox(height: 20),
              Text('Welcome to Maneyindha Marukatte', style: serif(22, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Sign in to manage your orders, saved addresses, and profile.',
                textAlign: TextAlign.center,
                style: sans(14, color: MMColors.textSecondary),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('Sign In / Register'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ResponsiveContainer(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: MMColors.sage,
                    backgroundImage: (auth.user?['avatarUrl'] != null)
                        ? NetworkImage(auth.user!['avatarUrl'].toString())
                        : null,
                    child: auth.user?['avatarUrl'] == null
                        ? const Icon(Icons.person, size: 48, color: MMColors.deepOlive)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: MMColors.deepOlive,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        auth.role.toUpperCase(),
                        style: sans(10, weight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Center(child: Text(auth.name, style: serif(24, weight: FontWeight.w700))),
            const SizedBox(height: 2),
            Center(child: Text(auth.email, style: sans(14, color: MMColors.textSecondary))),
            const SizedBox(height: 28),

            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined, color: MMColors.deepOlive),
                    title: const Text('Personal Details'),
                    subtitle: Text(auth.user?['phone']?.toString() ?? 'Add phone number'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _editPersonal(context, ref),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined, color: MMColors.deepOlive),
                    title: const Text('Saved Address'),
                    subtitle: Text(
                      ((auth.user?['addresses'] as List?)?.isNotEmpty == true)
                          ? (auth.user!['addresses'][0]['line1'] ?? 'Add address')
                          : 'Add address',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _editAddress(context, ref),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.favorite_outline_rounded, color: MMColors.terracotta),
                    title: const Text('My Wishlist'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showWishlist(context, ref),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.storefront_rounded, color: MMColors.olive),
                    title: const Text('Become a Women Entrepreneur'),
                    subtitle: const Text('Start selling your homemade creations'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final hasBusiness =
                          await ref.read(authProvider.notifier).switchRole('entrepreneur');
                      ref.invalidate(myBusinessesProvider);
                      ref.invalidate(ordersProvider);
                      if (context.mounted) {
                        context.go(hasBusiness ? '/seller' : '/seller/onboarding/business');
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.support_agent_rounded, color: MMColors.deepOlive),
                    title: const Text('Help & Customer Support'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Customer Support', style: serif(20, weight: FontWeight.w700)),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Have questions about an order or seller verification?',
                              style: TextStyle(height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: MMColors.cream,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.email_outlined,
                                      size: 20, color: MMColors.deepOlive),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SelectableText(
                                      'support@maneyindhamarukatte.in',
                                      style: sans(13, weight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: Color(0xFFBA1A1A)),
                    title: const Text('Logout', style: TextStyle(color: Color(0xFFBA1A1A))),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFBA1A1A)),
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
      ),
    );
  }
}
