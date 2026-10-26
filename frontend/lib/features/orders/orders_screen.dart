import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_state.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

const _statusLabels = {
  'pending': 'Order Placed (Waiting for Confirmation)',
  'confirmed': 'Order Confirmed by Entrepreneur',
  'preparing': 'Freshly Preparing in Kitchen',
  'ready': 'Packed & Ready for Pickup',
  'assigned': 'Delivery Partner Assigned',
  'picked_up': 'Picked Up by Courier',
  'out_for_delivery': 'Out for Delivery to Your Doorstep',
  'delivered': 'Delivered Successfully 🎉',
  'cancelled': 'Cancelled',
  'rejected': 'Declined by Shop',
  'refunded': 'Refund Processed',
  'payment_failed': 'Payment Failed',
};

Color _statusColor(String status) {
  switch (status) {
    case 'delivered':
      return MMColors.deepOlive;
    case 'out_for_delivery':
    case 'picked_up':
    case 'ready':
      return MMColors.olive;
    case 'preparing':
    case 'confirmed':
    case 'pending':
      return MMColors.marigold;
    case 'cancelled':
    case 'rejected':
    case 'payment_failed':
      return const Color(0xFFBA1A1A);
    default:
      return MMColors.textSecondary;
  }
}

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: EmptyView(
          message: 'Sign in to see your orders',
          subtitle: 'Track your delicious homemade food and artisan orders in real-time.',
          icon: Icons.receipt_long_outlined,
          buttonLabel: 'Sign In / Register',
          onButtonPressed: () => context.push('/login'),
        ),
      );
    }

    final orders = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Orders',
            onPressed: () => ref.invalidate(ordersProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: orders.when(
        loading: () => const LoadingView(message: 'Loading your orders…'),
        error: (e, _) => ErrorView(
          message: 'Could not load your orders.',
          onRetry: () => ref.invalidate(ordersProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyView(
              message: 'No orders placed yet',
              subtitle: 'Treat yourself to freshly prepared homemade food or handcrafted products.',
              icon: Icons.receipt_long_outlined,
              buttonLabel: 'Browse Marketplace',
              onButtonPressed: () => context.go('/app'),
            );
          }

          return ResponsiveContainer(
            maxWidth: 760,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) {
                final o = items[i];
                final amounts = (o['amounts'] as Map?) ?? {};
                final status = o['status']?.toString() ?? 'pending';
                final orderItems = (o['items'] as List?) ?? [];
                final business = o['business'];
                final businessName =
                    business is Map ? (business['name']?.toString() ?? '') : '';
                final isDelivered = status == 'delivered';
                final isCancelled = status == 'cancelled' || status == 'rejected';

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: Order ID + Status Chip
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Order #${o['orderNumber']}',
                                  style: serif(16, weight: FontWeight.w700),
                                ),
                                if (businessName.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'From $businessName',
                                    style: sans(13, color: MMColors.textSecondary),
                                  ),
                                ],
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status.replaceAll('_', ' ').toUpperCase(),
                                style: sans(
                                  11,
                                  weight: FontWeight.w800,
                                  color: _statusColor(status),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Status progress line
                        if (!isCancelled) ...[
                          _buildStepIndicator(status),
                          const SizedBox(height: 14),
                        ],

                        // Items list
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: MMColors.cream,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: orderItems.map((it) {
                              final itemMap = it as Map;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    const Icon(Icons.fiber_manual_record,
                                        size: 8, color: MMColors.olive),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${itemMap['name']} × ${itemMap['quantity']}',
                                        style: sans(14, color: MMColors.textPrimary),
                                      ),
                                    ),
                                    if (itemMap['unitPrice'] != null)
                                      Text(
                                        rupees(itemMap['unitPrice'] * (itemMap['quantity'] ?? 1)),
                                        style: sans(13, weight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Footer: Total & Actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Total Paid / Due',
                                    style: sans(12, color: MMColors.textMuted)),
                                Text(
                                  rupees(amounts['total']),
                                  style: sans(18,
                                      weight: FontWeight.w800,
                                      color: MMColors.deepOlive),
                                ),
                              ],
                            ),
                            if (isDelivered)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.star_outline_rounded, size: 16),
                                label: const Text('Rate Order'),
                                onPressed: () => _showReviewDialog(context, o, ref),
                              )
                            else
                              Text(
                                _statusLabels[status] ?? status,
                                style: sans(12,
                                    weight: FontWeight.w600,
                                    color: _statusColor(status)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildStepIndicator(String status) {
    final steps = ['pending', 'confirmed', 'preparing', 'out_for_delivery', 'delivered'];
    final currentIndex = steps.indexOf(status);
    final activeIndex = currentIndex == -1 ? 0 : currentIndex;

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIndex = i ~/ 2;
          final isCompleted = stepIndex < activeIndex;
          return Expanded(
            child: Container(
              height: 3,
              color: isCompleted ? MMColors.deepOlive : MMColors.border,
            ),
          );
        } else {
          final stepIndex = i ~/ 2;
          final isCompleted = stepIndex <= activeIndex;
          return Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? MMColors.deepOlive : MMColors.border,
            ),
          );
        }
      }),
    );
  }

  Future<void> _showReviewDialog(
    BuildContext context,
    Map<String, dynamic> order,
    WidgetRef ref,
  ) async {
    final items = (order['items'] as List?) ?? [];
    if (items.isEmpty) return;

    String selectedProductId = (items.first as Map)['product']?.toString() ?? '';
    String selectedProductName = (items.first as Map)['name']?.toString() ?? 'Product';
    int rating = 5;
    final commentController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.star_rounded, color: MMColors.terracotta, size: 24),
                const SizedBox(width: 8),
                Text('Rate Your Order', style: serif(18, weight: FontWeight.w700)),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (items.length > 1) ...[
                      Text('Select Item to Review:', style: sans(13, weight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedProductId,
                        decoration: const InputDecoration(isDense: true),
                        items: items.map((i) {
                          final itemMap = i as Map;
                          final pId = itemMap['product']?.toString() ?? '';
                          final pName = itemMap['name']?.toString() ?? 'Item';
                          return DropdownMenuItem(value: pId, child: Text(pName));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedProductId = val;
                              final match = items.firstWhere(
                                (it) => (it as Map)['product']?.toString() == val,
                                orElse: () => items.first,
                              ) as Map;
                              selectedProductName = match['name']?.toString() ?? 'Product';
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      Text(
                        selectedProductName,
                        style: sans(14, weight: FontWeight.w700, color: MMColors.deepOlive),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Your Rating:', style: sans(13, weight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final star = index + 1;
                        return IconButton(
                          iconSize: 32,
                          icon: Icon(
                            star <= rating ? Icons.star_rounded : Icons.star_border_rounded,
                            color: star <= rating ? const Color(0xFFE68A00) : Colors.grey,
                          ),
                          onPressed: () => setDialogState(() => rating = star),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: commentController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Share your feedback (optional)',
                        hintText: 'Taste, packaging, hygiene, craftsmanship...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: MMColors.deepOlive),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await ApiClient.dio.post('/reviews', data: {
                      'orderId': order['_id'],
                      'productId': selectedProductId,
                      'rating': rating,
                      'comment': commentController.text.trim(),
                    });
                    ref.invalidate(productReviewsProvider(selectedProductId));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thank you! Your verified review has been published ⭐'),
                          backgroundColor: MMColors.deepOlive,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(apiError(e))),
                      );
                    }
                  }
                },
                child: const Text('Submit Review'),
              ),
            ],
          );
        },
      ),
    );
  }
}
