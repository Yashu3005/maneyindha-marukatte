import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markRead(WidgetRef ref, String id) async {
    try {
      await ApiClient.dio.patch('/notifications/$id/read');
      ref.invalidate(notificationsProvider);
    } catch (_) {}
  }

  Future<void> _delete(WidgetRef ref, String id) async {
    try {
      await ApiClient.dio.delete('/notifications/$id');
      ref.invalidate(notificationsProvider);
    } catch (_) {}
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    try {
      await ApiClient.dio.delete('/notifications');
      ref.invalidate(notificationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications cleared'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      appBar: AppBar(
        backgroundColor: MMColors.warmIvory,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MMColors.primaryGreen),
          onPressed: () => context.pop(),
        ),
        title: Text('Notifications', style: serif(20, color: MMColors.primaryGreen)),
        actions: [
          TextButton(
            onPressed: () => _clearAll(context, ref),
            child: const Text('Clear All', style: TextStyle(color: MMColors.primaryGreen, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
        elevation: 0,
      ),
      body: notificationsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Could not load notifications.',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (data) {
          final items = (data['items'] as List?) ?? [];

          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.notifications_none, size: 72, color: MMColors.secondaryGreen),
                    const SizedBox(height: 16),
                    Text('No Notifications Yet',
                        style: serif(22, color: MMColors.primaryGreen, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text("We'll notify you about\nyour orders and updates.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MMColors.textSecondary, fontSize: 15)),
                  ],
                ),
              ),
            );
          }

          // Chronological grouping
          final today = <Map<String, dynamic>>[];
          final yesterday = <Map<String, dynamic>>[];
          final older = <Map<String, dynamic>>[];

          final now = DateTime.now();
          for (final raw in items) {
            final notif = Map<String, dynamic>.from(raw as Map);
            final createdAt = DateTime.tryParse(notif['createdAt']?.toString() ?? '') ?? now;
            final diff = now.difference(createdAt);
            if (diff.inHours < 24 && now.day == createdAt.day) {
              today.add(notif);
            } else if (diff.inDays <= 1) {
              yesterday.add(notif);
            } else {
              older.add(notif);
            }
          }

          Widget buildGroup(String title, List<Map<String, dynamic>> group) {
            if (group.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: MMColors.textSecondary)),
                ),
                ...group.map((item) {
                  final notifId = item['_id']?.toString() ?? '';
                  final isRead = item['isRead'] == true;
                  final titleText = item['title']?.toString() ?? 'Notification';
                  final bodyText = item['body']?.toString() ?? '';

                  return Dismissible(
                    key: Key(notifId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red.shade400,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _delete(ref, notifId),
                    child: Container(
                      color: isRead ? Colors.transparent : MMColors.softYellow.withValues(alpha: 0.35),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: MMColors.sage,
                              child: Icon(
                                item['type'] == 'order'
                                    ? Icons.receipt_long
                                    : item['type'] == 'refund'
                                        ? Icons.replay
                                        : Icons.notifications,
                                color: MMColors.primaryGreen,
                                size: 20,
                              ),
                            ),
                            if (!isRead)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(titleText,
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                              color: MMColors.textPrimary,
                            )),
                        subtitle: Text(bodyText,
                            style: const TextStyle(color: MMColors.textSecondary, fontSize: 13)),
                        onTap: () {
                          if (!isRead) _markRead(ref, notifId);
                          final orderId = item['data']?['orderId'];
                          if (orderId != null) {
                            context.push('/orders');
                          }
                        },
                      ),
                    ),
                  );
                }),
              ],
            );
          }

          return ListView(
            children: [
              buildGroup('Today', today),
              buildGroup('Yesterday', yesterday),
              buildGroup('Last Week', older),
            ],
          );
        },
      ),
    );
  }
}
