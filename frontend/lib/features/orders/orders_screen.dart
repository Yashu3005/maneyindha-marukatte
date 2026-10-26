import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import '../checkout/pay_flow.dart';

const _statusLabels = {
  'pending': 'Waiting for shop to confirm',
  'confirmed': 'Confirmed',
  'preparing': 'Being prepared',
  'ready': 'Ready',
  'assigned': 'Delivery partner assigned',
  'picked_up': 'Picked up',
  'out_for_delivery': 'Out for delivery',
  'delivered': 'Delivered',
  'cancelled': 'Cancelled',
  'rejected': 'Rejected',
  'refunded': 'Refunded',
  'payment_failed': 'Payment failed',
};

// Position of each status on the 5-step tracker. Statuses not listed (cancelled, rejected…) get no tracker.
const _trackerStep = {
  'pending': 0, 'confirmed': 1, 'preparing': 2, 'ready': 2,
  'assigned': 3, 'picked_up': 3, 'out_for_delivery': 3, 'delivered': 4,
};
const _trackerLabels = ['Placed', 'Confirmed', 'Preparing', 'On the way', 'Delivered'];

Color _statusColor(String status) {
  switch (status) {
    case 'delivered': return MMColors.moss;
    case 'cancelled':
    case 'rejected':
    case 'payment_failed': return Colors.red.shade400;
    case 'refunded': return Colors.blueGrey;
    case 'pending': return MMColors.marigold;
    default: return MMColors.clay;
  }
}

class _OrderTracker extends StatelessWidget {
  final int step;
  const _OrderTracker({required this.step});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: List.generate(_trackerLabels.length * 2 - 1, (i) {
        if (i.isOdd) {
          final done = (i ~/ 2) < step;
          return Expanded(
            child: Container(height: 3, color: done ? MMColors.moss : MMColors.sage),
          );
        }
        final idx = i ~/ 2;
        final done = idx <= step;
        return Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? MMColors.moss : MMColors.card,
            border: Border.all(color: done ? MMColors.moss : MMColors.sage, width: 2),
          ),
          child: done ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
        );
      })),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_trackerLabels.length, (i) => Text(
          _trackerLabels[i],
          style: TextStyle(
            fontSize: 10,
            fontWeight: i == step ? FontWeight.w700 : FontWeight.w400,
            color: i <= step ? MMColors.deepOlive : Colors.black45,
          ),
        )),
      ),
    ]);
  }
}

bool _needsPayment(Map o) {
  final p = o['payment'];
  return p is Map &&
      p['method'] == 'razorpay' &&
      p['status'] != 'paid' &&
      o['status'] == 'pending';
}

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('My orders')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.push('/login'),
            child: const Text('Sign in to see your orders'),
          ),
        ),
      );
    }

    final orders = ref.watch(ordersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: orders.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: 'Could not load orders.',
            onRetry: () => ref.invalidate(ordersProvider)),
        data: (items) => items.isEmpty
            ? const EmptyView(message: 'No orders yet.\nYour orders will show up here.')
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final o = items[i];
                      final amounts = (o['amounts'] as Map?) ?? {};
                      final status = o['status']?.toString() ?? '';
                      final orderItems = (o['items'] as List?) ?? [];
                      final color = _statusColor(status);
                      final step = _trackerStep[status];
                      return SoftCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text('${o['orderNumber']}', style: serif(16)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(_statusLabels[status] ?? status,
                                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Text(
                            orderItems
                                .map((it) => '${(it as Map)['name']} × ${it['quantity']}')
                                .join(', '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (step != null) ...[
                            const SizedBox(height: 14),
                            _OrderTracker(step: step),
                          ],
                          const SizedBox(height: 10),
                          Row(children: [
                            Text(rupees(amounts['total']),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(width: 8),
                            if (o['payment'] is Map && (o['payment'] as Map)['status'] == 'paid')
                              const Chip(
                                avatar: Icon(Icons.check_circle, size: 14, color: MMColors.moss),
                                label: Text('Paid online'),
                                visualDensity: VisualDensity.compact,
                              ),
                          ]),
                          if (_needsPayment(o))
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final r = await payForOrder(o['_id'].toString());
                                  ref.invalidate(ordersProvider);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(content: Text(r.message)));
                                  }
                                },
                                icon: const Icon(Icons.lock_outline, size: 18),
                                label: const Text('Payment pending · Pay now'),
                              ),
                            ),
                        ]),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}
