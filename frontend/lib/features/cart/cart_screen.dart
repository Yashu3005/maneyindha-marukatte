import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final Set<String> _selectedProductIds = {};
  String? _selectedStoreId;

  Future<void> _updateQty(String productId, int quantity) async {
    if (quantity <= 0) return;
    try {
      await ApiClient.dio.patch('/cart/items',
          data: {'productId': productId, 'quantity': quantity});
      ref.invalidate(cartProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _removeItem(String productId) async {
    try {
      await ApiClient.dio.patch('/cart/items',
          data: {'productId': productId, 'quantity': 0});
      setState(() {
        _selectedProductIds.remove(productId);
        if (_selectedProductIds.isEmpty) _selectedStoreId = null;
      });
      ref.invalidate(cartProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Removed from Cart'),
            duration: Duration(seconds: 2),
          ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _moveToWishlist(String productId) async {
    try {
      await ApiClient.dio.post('/wishlist/products', data: {'productId': productId});
      await ApiClient.dio.patch('/cart/items', data: {'productId': productId, 'quantity': 0});
      setState(() {
        _selectedProductIds.remove(productId);
        if (_selectedProductIds.isEmpty) _selectedStoreId = null;
      });
      ref.invalidate(cartProvider);
      ref.invalidate(wishlistProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Moved to Wishlist ❤️'),
            duration: Duration(seconds: 2),
          ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  void _onToggleProduct(String productId, String storeId, bool? checked) {
    if (checked == true) {
      if (_selectedStoreId != null && _selectedStoreId != storeId) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            backgroundColor: MMColors.primaryGreen,
            content: Text('Please place separate orders for products from different entrepreneurs.'),
            duration: Duration(seconds: 3),
          ));
        return;
      }
      setState(() {
        _selectedStoreId = storeId;
        _selectedProductIds.add(productId);
      });
    } else {
      setState(() {
        _selectedProductIds.remove(productId);
        if (_selectedProductIds.isEmpty) {
          _selectedStoreId = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) {
      return Scaffold(
        backgroundColor: MMColors.warmIvory,
        appBar: AppBar(
          backgroundColor: MMColors.warmIvory,
          title: Text('My Cart', style: serif(20, color: MMColors.primaryGreen)),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 72, color: MMColors.secondaryGreen),
              const SizedBox(height: 16),
              Text('Sign in to view your Cart', style: serif(18, color: MMColors.primaryGreen)),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                onPressed: () => context.push('/login'),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ),
      );
    }

    final cartAsync = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      appBar: AppBar(
        backgroundColor: MMColors.warmIvory,
        title: Text('My Cart', style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
        elevation: 0,
      ),
      body: cartAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: apiError(e),
          onRetry: () => ref.invalidate(cartProvider),
        ),
        data: (cart) {
          final items = (cart['items'] as List?) ?? [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.shopping_bag_outlined, size: 72, color: MMColors.secondaryGreen),
                    const SizedBox(height: 16),
                    Text('Your Cart is Empty',
                        style: serif(22, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Add products from local entrepreneurs\nto start shopping.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MMColors.textSecondary, fontSize: 15)),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                      onPressed: () => context.go('/app'),
                      child: const Text('Continue Shopping'),
                    ),
                  ],
                ),
              ),
            );
          }

          // Group products by entrepreneur
          final storeGroups = <String, List<Map<String, dynamic>>>{};
          final storeInfo = <String, Map<String, dynamic>>{};

          for (final raw in items) {
            final item = Map<String, dynamic>.from(raw as Map);
            final p = item['product'] is Map ? Map<String, dynamic>.from(item['product']) : {};
            final business = p['business'] is Map ? Map<String, dynamic>.from(p['business']) : {};
            final bId = business['_id']?.toString() ?? 'store';

            storeGroups.putIfAbsent(bId, () => []).add(item);
            storeInfo.putIfAbsent(bId, () => Map<String, dynamic>.from(business));
          }

          // Compute selected summary
          num selectedSubtotal = 0;
          num deliveryCharge = 0;
          final selectedItems = <Map<String, dynamic>>[];

          for (final raw in items) {
            final item = Map<String, dynamic>.from(raw as Map);
            final p = item['product'] is Map ? Map<String, dynamic>.from(item['product']) : {};
            final pId = p['_id']?.toString() ?? '';
            final qty = (item['quantity'] ?? 1) as num;
            final price = (p['price'] ?? 0) as num;

            if (_selectedProductIds.contains(pId)) {
              selectedSubtotal += (price * qty);
              selectedItems.add({
                'productId': pId,
                'name': p['name'],
                'price': price,
                'quantity': qty,
                'customization': item['customization'] ?? '',
                'images': p['images'],
              });
              if (p['deliveryOptions'] is Map) {
                final d = p['deliveryOptions'] as Map;
                if (d['freeDelivery'] == true) {
                  deliveryCharge = 0;
                } else if (d['deliveryCharge'] != null) {
                  deliveryCharge = d['deliveryCharge'] as num;
                }
              } else {
                deliveryCharge = 30;
              }
            }
          }

          final num totalAmount = selectedSubtotal > 0 ? (selectedSubtotal + deliveryCharge) : 0;
          final bool canCheckout = selectedItems.isNotEmpty && _selectedStoreId != null;

          return Column(
            children: [
              // Header item count
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${items.length} ${items.length == 1 ? 'Item' : 'Items'} in Cart',
                    style: const TextStyle(color: MMColors.textSecondary, fontSize: 13),
                  ),
                ),
              ),

              // Grouped Store Items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: storeGroups.entries.map((entry) {
                    final storeId = entry.key;
                    final groupItems = entry.value;
                    final store = storeInfo[storeId] ?? {};
                    final storeName = store['name']?.toString() ?? 'Artisan Store';
                    final isOpen = store['isOpen'] != false;

                    return Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: MMColors.sage, width: 0.8),
                      ),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Store Header
                            Row(
                              children: [
                                const Icon(Icons.storefront, size: 20, color: MMColors.primaryGreen),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(storeName,
                                          style: serif(16,
                                              color: MMColors.primaryGreen,
                                              weight: FontWeight.w700)),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.verified, size: 14, color: MMColors.primaryGreen),
                                    ],
                                  ),
                                ),
                                if (!isOpen)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('Store Closed',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700)),
                                  ),
                              ],
                            ),
                            const Text('Estimated Delivery: Today before 5:30 PM',
                                style: TextStyle(color: MMColors.textSecondary, fontSize: 12)),
                            const Divider(height: 18),

                            // Items in this store
                            ...groupItems.map((rawItem) {
                              final p = rawItem['product'] is Map
                                  ? Map<String, dynamic>.from(rawItem['product'])
                                  : {};
                              final pId = p['_id']?.toString() ?? '';
                              final qty = (rawItem['quantity'] ?? 1) as int;
                              final images = (p['images'] as List?) ?? [];
                              final firstImg = images.isNotEmpty ? images.first.toString() : null;
                              final isChecked = _selectedProductIds.contains(pId);
                              final stock = (p['stock'] ?? 10) as num;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Checkbox(
                                      activeColor: MMColors.primaryGreen,
                                      value: isChecked,
                                      onChanged: (val) => _onToggleProduct(pId, storeId, val),
                                    ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(width: 68, height: 68, child: NetImage(firstImg)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p['name']?.toString() ?? 'Product',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                                color: MMColors.textPrimary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            rupees(p['price']),
                                            style: const TextStyle(
                                                color: MMColors.primaryGreen,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14),
                                          ),
                                          if (rawItem['customization'] != null &&
                                              rawItem['customization'].toString().isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Note: ${rawItem['customization']}',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: MMColors.textSecondary,
                                                  fontStyle: FontStyle.italic),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                decoration: BoxDecoration(
                                                  border: Border.all(color: MMColors.sage),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      constraints: const BoxConstraints(),
                                                      padding: const EdgeInsets.all(4),
                                                      icon: const Icon(Icons.remove, size: 16),
                                                      onPressed: qty > 1
                                                          ? () => _updateQty(pId, qty - 1)
                                                          : null,
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                                      child: Text('$qty',
                                                          style: const TextStyle(fontWeight: FontWeight.w700)),
                                                    ),
                                                    IconButton(
                                                      constraints: const BoxConstraints(),
                                                      padding: const EdgeInsets.all(4),
                                                      icon: const Icon(Icons.add, size: 16),
                                                      onPressed: qty < stock
                                                          ? () => _updateQty(pId, qty + 1)
                                                          : null,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Spacer(),
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                    visualDensity: VisualDensity.compact,
                                                    padding: EdgeInsets.zero),
                                                onPressed: () => _moveToWishlist(pId),
                                                child: const Text('❤️ Wishlist',
                                                    style: TextStyle(
                                                        color: MMColors.primaryGreen, fontSize: 12)),
                                              ),
                                              IconButton(
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.all(4),
                                                icon: const Icon(Icons.delete_outline,
                                                    size: 18, color: Colors.red),
                                                onPressed: () => _removeItem(pId),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Sticky Bottom Order Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(top: BorderSide(color: MMColors.sage, width: 1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal', style: TextStyle(color: MMColors.textSecondary)),
                          Text(rupees(selectedSubtotal),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Delivery Charge', style: TextStyle(color: MMColors.textSecondary)),
                          Text(rupees(deliveryCharge),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const Divider(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total',
                              style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                          Text(rupees(totalAmount),
                              style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: MMColors.primaryGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: canCheckout
                              ? () {
                                  context.push('/checkout', extra: {
                                    'businessId': _selectedStoreId,
                                    'items': selectedItems,
                                    'subtotal': selectedSubtotal,
                                    'deliveryFee': deliveryCharge,
                                    'total': totalAmount,
                                  });
                                }
                              : null,
                          child: Text(
                            canCheckout
                                ? 'Proceed to Checkout (${selectedItems.length})'
                                : 'Select items to checkout',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ),
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
}
