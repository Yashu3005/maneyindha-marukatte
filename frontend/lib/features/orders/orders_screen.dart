import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';

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

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  Future<void> _verifyPayment(BuildContext context, WidgetRef ref, String orderId) async {
    try {
      final res = await ApiClient.dio.post('/payments/verify', data: {'orderId': orderId});
      final paid = (res.data['data'] as Map)['paid'] == true;
      ref.invalidate(ordersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(paid ? 'Payment confirmed ✓' : 'Payment not completed yet')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

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
            ? const EmptyView(message: 'No orders yet.')
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
                      return Card(
                        child: ListTile(
                          title: Text('${o['orderNumber']} · ${rupees(amounts['total'])}'),
                          subtitle: Text(
                            orderItems
                                .map((it) => '${(it as Map)['name']} × ${it['quantity']}')
                                .join(', '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Chip(
                                label: Text(_statusLabels[status] ?? status),
                                visualDensity: VisualDensity.compact,
                              ),
                              if ((o['payment'] as Map?)?['status'] == 'paid')
                                const Text('Paid ✓',
                                    style: TextStyle(color: Colors.teal, fontSize: 12))
                              else if ((o['payment'] as Map?)?['method'] == 'razorpay')
                                TextButton(
                                  onPressed: () => _verifyPayment(
                                      context, ref, o['_id'].toString()),
                                  child: const Text('Verify payment'),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}
