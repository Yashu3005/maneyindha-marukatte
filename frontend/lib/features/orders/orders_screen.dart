import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  int _selectedTab = 0; // 0: Active, 1: Completed, 2: Cancelled

  void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MMColors.warmIvory,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _OrderDetailsSheet(order: order),
    );
  }

  void _showWriteReviewDialog(BuildContext context, Map<String, dynamic> order) {
    int rating = 5;
    final commentCtrl = TextEditingController();
    final items = (order['items'] as List?) ?? [];
    final firstItem = items.isNotEmpty ? items.first : null;
    final productId = firstItem?['product'] is Map
        ? firstItem['product']['_id']
        : firstItem?['product'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Write a Review', style: serif(18, color: MMColors.primaryGreen)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: MMColors.accentGold,
                      size: 32,
                    ),
                    onPressed: () => setDialogState(() => rating = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Your Review',
                  hintText: 'Share your experience with this home artisan product...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: MMColors.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () async {
                try {
                  await ApiClient.dio.post('/reviews', data: {
                    'orderId': order['_id'],
                    'businessId': order['business']?['_id'] ?? order['business'],
                    'productId': productId,
                    'rating': rating,
                    'comment': commentCtrl.text.trim(),
                  });
                  ref.invalidate(ordersProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Review submitted successfully! Thank you ⭐')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Submit Review'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) {
      return Scaffold(
        backgroundColor: MMColors.warmIvory,
        appBar: AppBar(
          backgroundColor: MMColors.warmIvory,
          title: Text('My Orders', style: serif(20, color: MMColors.primaryGreen)),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 72, color: MMColors.secondaryGreen),
              const SizedBox(height: 16),
              Text('Sign in to view your orders', style: serif(18, color: MMColors.primaryGreen)),
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

    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      appBar: AppBar(
        backgroundColor: MMColors.warmIvory,
        title: Text('My Orders', style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Order Filter Tabs: Active | Completed | Cancelled
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('Active', 0),
                const SizedBox(width: 8),
                _buildFilterChip('Completed', 1),
                const SizedBox(width: 8),
                _buildFilterChip('Cancelled', 2),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Orders List
          Expanded(
            child: ordersAsync.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                message: 'Could not load orders.',
                onRetry: () => ref.invalidate(ordersProvider),
              ),
              data: (allOrders) {
                final filtered = allOrders.where((o) {
                  final s = o['status']?.toString() ?? 'pending';
                  if (_selectedTab == 0) {
                    return !['delivered', 'cancelled', 'rejected', 'refunded'].contains(s);
                  } else if (_selectedTab == 1) {
                    return ['delivered', 'refunded'].contains(s);
                  } else {
                    return ['cancelled', 'rejected'].contains(s);
                  }
                }).toList();

                if (filtered.isEmpty) {
                  final emptyMsgs = [
                    'No Active Orders\nYour current orders will appear here.',
                    'No Completed Orders Yet\nYour delivered orders will appear here.',
                    'No Cancelled Orders',
                  ];
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long, size: 64, color: MMColors.secondaryGreen),
                          const SizedBox(height: 16),
                          Text(
                            emptyMsgs[_selectedTab],
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: MMColors.textSecondary, fontSize: 15),
                          ),
                          if (_selectedTab == 0) ...[
                            const SizedBox(height: 20),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                              onPressed: () => context.go('/app'),
                              child: const Text('Start Shopping'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final o = filtered[i];
                    final amounts = (o['amounts'] as Map?) ?? {};
                    final items = (o['items'] as List?) ?? [];
                    final status = o['status']?.toString() ?? 'pending';
                    final storeName = (o['business'] is Map)
                        ? o['business']['name']?.toString() ?? 'Artisan Store'
                        : 'Artisan Store';

                    final displayStatus = status == 'pending'
                        ? 'Order Confirmed'
                        : status == 'preparing'
                            ? 'Preparing'
                            : status == 'ready'
                                ? (o['isSelfPickup'] == true ? 'Ready for Pickup' : 'Ready')
                                : status == 'out_for_delivery'
                                    ? 'Out for Delivery'
                                    : status == 'delivered'
                                        ? 'Delivered'
                                        : status == 'cancelled'
                                            ? 'Cancelled'
                                            : status;

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
                                Text('Order #${o['orderNumber'] ?? ''}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: status == 'delivered'
                                        ? Colors.green.shade100
                                        : status == 'cancelled'
                                            ? Colors.red.shade100
                                            : MMColors.sage,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    displayStatus,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color: status == 'delivered'
                                          ? Colors.green.shade800
                                          : status == 'cancelled'
                                              ? Colors.red.shade800
                                              : MMColors.primaryGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(storeName,
                                    style: serif(15, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                                const SizedBox(width: 4),
                                const Icon(Icons.verified, size: 14, color: MMColors.primaryGreen),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${items.length} ${items.length == 1 ? 'Item' : 'Items'} • ${rupees(amounts['total'])}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            if (status != 'delivered' && status != 'cancelled') ...[
                              const SizedBox(height: 4),
                              const Text('Expected Delivery: Today before 5:30 PM',
                                  style: TextStyle(color: MMColors.textSecondary, fontSize: 12)),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: MMColors.primaryGreen),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  onPressed: () => _showOrderDetails(context, o),
                                  child: const Text('View Details',
                                      style: TextStyle(color: MMColors.primaryGreen, fontWeight: FontWeight.w700)),
                                ),
                                const Spacer(),
                                if (status == 'delivered')
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: MMColors.primaryGreen,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ),
                                    onPressed: () => _showWriteReviewDialog(context, o),
                                    child: const Text('Write Review', style: TextStyle(fontWeight: FontWeight.w700)),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedTab == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: MMColors.primaryGreen,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : MMColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? MMColors.primaryGreen : MMColors.sage),
      ),
      onSelected: (_) => setState(() => _selectedTab = index),
    );
  }
}

class _OrderDetailsSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  const _OrderDetailsSheet({required this.order});

  @override
  ConsumerState<_OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends ConsumerState<_OrderDetailsSheet> {
  late Map<String, dynamic> _currentOrder;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MMColors.warmIvory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Order?'),
        content: const Text('Are you sure you want to cancel this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order', style: TextStyle(color: MMColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final res = await ApiClient.dio.post('/orders/${_currentOrder['_id']}/cancel');
        ref.invalidate(ordersProvider);
        setState(() => _currentOrder = Map<String, dynamic>.from(res.data['data'] as Map));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order Cancelled Successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
        }
      }
    }
  }

  void _requestAfterSales(String type) {
    String selectedReason = 'Product damaged';
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(type == 'refund' ? 'Request Refund' : 'Request Replacement',
              style: serif(18, color: MMColors.primaryGreen)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  'Product damaged',
                  'Wrong product received',
                  'Product quality issue',
                  'Other',
                ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setDialogState(() => selectedReason = v ?? 'Product damaged'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () async {
                try {
                  final res = await ApiClient.dio.post(
                    '/orders/${_currentOrder['_id']}/after-sales',
                    data: {
                      'type': type,
                      'reason': selectedReason,
                      'description': descCtrl.text.trim(),
                    },
                  );
                  ref.invalidate(ordersProvider);
                  setState(() => _currentOrder = Map<String, dynamic>.from(res.data['data'] as Map));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${type == 'refund' ? 'Refund' : 'Replacement'} request submitted')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startReturn() async {
    try {
      final res = await ApiClient.dio.post('/orders/${_currentOrder['_id']}/return/start');
      ref.invalidate(ordersProvider);
      setState(() => _currentOrder = Map<String, dynamic>.from(res.data['data'] as Map));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return initiated. Please hand over the package to the pickup agent.')),
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
    final o = _currentOrder;
    final amounts = (o['amounts'] as Map?) ?? {};
    final items = (o['items'] as List?) ?? [];
    final status = o['status']?.toString() ?? 'pending';
    final isPickup = o['isSelfPickup'] == true;
    final storeName = (o['business'] is Map)
        ? o['business']['name']?.toString() ?? 'Artisan Store'
        : 'Artisan Store';
    final afterSales = (o['afterSales'] as Map?) ?? {};

    final canCancel = status == 'pending' || status == 'confirmed';
    final isDelivered = status == 'delivered';

    // Status timeline steps
    final steps = isPickup
        ? ['Order Confirmed', 'Preparing', 'Ready for Pickup', 'Delivered']
        : ['Order Confirmed', 'Preparing', 'Out for Delivery', 'Delivered'];

    int currentStep = 0;
    if (status == 'confirmed' || status == 'pending') {
      currentStep = 0;
    } else if (status == 'preparing') {
      currentStep = 1;
    } else if (status == 'ready' || status == 'out_for_delivery') {
      currentStep = 2;
    } else if (status == 'delivered') {
      currentStep = 3;
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Order #${o['orderNumber'] ?? ''}',
                  style: serif(20, color: MMColors.primaryGreen, weight: FontWeight.w700)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          Text('By $storeName ✓', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const Divider(height: 20),

          // Visual Status Timeline
          if (status != 'cancelled' && status != 'rejected') ...[
            Text('Order Status', style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: List.generate(steps.length, (i) {
                final isDone = i <= currentStep;
                final isCurrent = i == currentStep;
                return Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (i > 0)
                            Expanded(
                              child: Container(
                                height: 3,
                                color: isDone ? MMColors.primaryGreen : MMColors.sage,
                              ),
                            ),
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: isDone ? MMColors.primaryGreen : MMColors.sage,
                            child: Icon(
                              isDone ? Icons.check : Icons.circle,
                              size: 14,
                              color: isDone ? Colors.white : MMColors.textSecondary,
                            ),
                          ),
                          if (i < steps.length - 1)
                            Expanded(
                              child: Container(
                                height: 3,
                                color: (i < currentStep) ? MMColors.primaryGreen : MMColors.sage,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        steps[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCurrent ? MMColors.primaryGreen : MMColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel, color: Colors.red),
                  const SizedBox(width: 10),
                  Text('This order was cancelled.',
                      style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // After Sales Request Status banner if raised
          if (afterSales['isRequested'] == true) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MMColors.cream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MMColors.sage),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.replay, color: MMColors.primaryGreen, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        '${afterSales['type'] == 'refund' ? 'Refund' : 'Replacement'} Request: ${(afterSales['status'] ?? '').toString().toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Reason: ${afterSales['reason'] ?? ''}', style: const TextStyle(fontSize: 12)),
                  if (afterSales['rejectionReason'] != null)
                    Text('Rejection Note: ${afterSales['rejectionReason']}',
                        style: const TextStyle(fontSize: 12, color: Colors.red)),
                  if (afterSales['returnRequired'] == true &&
                      afterSales['returnStatus'] == 'return_required') ...[
                    const SizedBox(height: 8),
                    const Text('Return Required: Please return the product to complete this request.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
                      onPressed: _startReturn,
                      child: const Text('Start Return'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Items Ordered
          Text('Items Ordered (${items.length})',
              style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...items.map((it) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it['name']?.toString() ?? 'Item',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        if (it['customization'] != null && it['customization'].toString().isNotEmpty)
                          Text('Customization: ${it['customization']}',
                              style: const TextStyle(fontSize: 12, color: MMColors.textSecondary)),
                        Text('Qty: ${it['quantity']}',
                            style: const TextStyle(fontSize: 12, color: MMColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(rupees((it['unitPrice'] ?? 0) * (it['quantity'] ?? 1)),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            );
          }),
          const Divider(height: 20),

          // Price Summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Items Total', style: TextStyle(color: MMColors.textSecondary)),
              Text(rupees(amounts['subtotal']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Delivery Fee', style: TextStyle(color: MMColors.textSecondary)),
              Text(isPickup ? 'FREE (Pickup)' : rupees(amounts['deliveryFee']),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Grand Total', style: serif(16, color: MMColors.primaryGreen, weight: FontWeight.w700)),
              Text(rupees(amounts['total']),
                  style: serif(18, color: MMColors.primaryGreen, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 20),

          // Cancel Action (only if allowed)
          if (canCancel) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _cancelOrder,
                child: const Text('Cancel Order',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
          ] else if (status != 'delivered' && status != 'cancelled') ...[
            const Text('This order cannot be cancelled because preparation has already started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MMColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
            const SizedBox(height: 10),
          ],

          // After-Sales Actions (Refund / Replacement if delivered)
          if (isDelivered && afterSales['isRequested'] != true) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: MMColors.primaryGreen),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _requestAfterSales('refund'),
                    child: const Text('Request Refund', style: TextStyle(color: MMColors.primaryGreen)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: MMColors.primaryGreen),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _requestAfterSales('replacement'),
                    child: const Text('Request Replacement', style: TextStyle(color: MMColors.primaryGreen)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
