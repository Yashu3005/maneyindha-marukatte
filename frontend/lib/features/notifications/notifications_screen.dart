import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

const _icons = {
  'order': Icons.receipt_long, 'payment': Icons.payments, 'refund': Icons.replay,
  'review': Icons.star, 'promotion': Icons.local_offer, 'verification': Icons.verified,
  'delivery': Icons.delivery_dining, 'reward': Icons.savings, 'system': Icons.info,
  'message': Icons.chat_bubble,
};

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the screen marks everything read.
    Future.microtask(() async {
      try {
        await ApiClient.dio.patch('/notifications/read-all');
        ref.invalidate(notificationsProvider);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: data.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: apiError(e),
            onRetry: () => ref.invalidate(notificationsProvider)),
        data: (d) {
          final items = d['items'] as List<Map<String, dynamic>>;
          if (items.isEmpty) {
            return const EmptyView(message: 'No notifications yet.');
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final n = items[i];
                  final unread = n['isRead'] != true;
                  return Card(
                    color: unread ? MMColors.sage : null,
                    child: ListTile(
                      leading: Icon(_icons[n['type']] ?? Icons.notifications,
                          color: MMColors.deepOlive),
                      title: Text(n['title']?.toString() ?? ''),
                      subtitle: Text(n['body']?.toString() ?? ''),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
