import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

final availableDeliveriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/delivery/available');
  return (res.data['data'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

class DeliveryShell extends ConsumerStatefulWidget {
  const DeliveryShell({super.key});
  @override
  ConsumerState<DeliveryShell> createState() => _DeliveryShellState();
}

class _DeliveryShellState extends ConsumerState<DeliveryShell> {
  int _index = 0;

  Future<void> _accept(String orderId) async {
    try {
      await ApiClient.dio.post('/delivery/accept', data: {'orderId': orderId});
      ref.invalidate(availableDeliveriesProvider);
      ref.invalidate(ordersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Delivery accepted — pick it up!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _transition(String orderId, String status) async {
    String? otp;
    if (status == 'delivered') {
      final controller = TextEditingController();
      otp = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delivery OTP'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
                hintText: 'Ask the customer for their 4-digit code'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Confirm delivery')),
          ],
        ),
      );
      if (otp == null || otp.isEmpty) return;
    }
    try {
      await ApiClient.dio.patch('/orders/$orderId/status',
          data: {'status': status, if (otp != null) 'otp': otp});
      ref.invalidate(ordersProvider);
      if (mounted && status == 'delivered') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Delivered ✓ Great work!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (auth.role != 'delivery_partner') {
      return Scaffold(
        appBar: AppBar(title: const Text('Deliveries')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Sign in as a delivery partner'),
          ),
        ),
      );
    }

    final available = ref.watch(availableDeliveriesProvider);
    final mine = ref.watch(ordersProvider); // delivery role → own deliveries

    const nextStep = {
      'assigned': 'picked_up',
      'picked_up': 'out_for_delivery',
      'out_for_delivery': 'delivered',
    };

    final tabs = [
      // ---- Available pool ----
      available.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: apiError(e),
            onRetry: () => ref.invalidate(availableDeliveriesProvider)),
        data: (items) => items.isEmpty
            ? const EmptyView(message: 'No deliveries waiting right now.\nPull down to refresh soon!')
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(availableDeliveriesProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final o = items[i];
                    final shop = (o['business'] as Map?) ?? {};
                    final address = (o['deliveryAddress'] as Map?) ?? {};
                    return Card(
                      child: ListTile(
                        title: Text('${o['orderNumber']} · ${rupees((o['amounts'] as Map?)?['total'])}'),
                        subtitle: Text('Pickup: ${shop['name'] ?? '-'}\n'
                            'Drop: ${address['line1'] ?? '-'}, ${address['city'] ?? ''}'),
                        isThreeLine: true,
                        trailing: FilledButton(
                          onPressed: () => _accept(o['_id'].toString()),
                          child: const Text('Accept'),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
      // ---- My deliveries ----
      mine.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: apiError(e), onRetry: () => ref.invalidate(ordersProvider)),
        data: (items) {
          final active = items
              .where((o) => nextStep.containsKey(o['status']))
              .toList();
          if (active.isEmpty) {
            return const EmptyView(message: 'No active deliveries.\nAccept one from the Available tab!');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: active.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final o = active[i];
              final status = o['status'].toString();
              final next = nextStep[status]!;
              return Card(
                child: ListTile(
                  title: Text('${o['orderNumber']} · ${(o['business'] as Map?)?['name'] ?? ''}'),
                  subtitle: Text(status.replaceAll('_', ' ')),
                  trailing: FilledButton(
                    onPressed: () => _transition(o['_id'].toString(), next),
                    child: Text(next == 'delivered'
                        ? 'Delivered (OTP)'
                        : next.replaceAll('_', ' ')),
                  ),
                ),
              );
            },
          );
        },
      ),
      // ---- Earnings (₹25 per delivered order for the MVP) ----
      mine.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e)),
        data: (items) {
          final done = items.where((o) => o['status'] == 'delivered').length;
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$done deliveries completed', style: serif(20)),
              const SizedBox(height: 8),
              Text('Earnings: ${rupees(done * 25)}', style: serif(28)),
              const SizedBox(height: 8),
              const Text('₹25 per delivery · payouts arrive with the payments phase'),
            ]),
          );
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Deliveries · ${auth.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/');
            },
          ),
        ],
      ),
      body: tabs[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          ref.invalidate(availableDeliveriesProvider);
          ref.invalidate(ordersProvider);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Available'),
          NavigationDestination(icon: Icon(Icons.delivery_dining), label: 'My deliveries'),
          NavigationDestination(icon: Icon(Icons.savings), label: 'Earnings'),
        ],
      ),
    );
  }
}
