import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

/// A bell with an unread badge. Re-checks every 30 seconds while it is on screen.
class NotificationBell extends ConsumerStatefulWidget {
  final Color color;
  const NotificationBell({super.key, this.color = Colors.white});
  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) ref.invalidate(notificationsProvider); });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final unread = (ref.watch(notificationsProvider).valueOrNull?['unread'] as num?)?.toInt() ?? 0;
    return IconButton(
      tooltip: unread > 0 ? '$unread unread notifications' : 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: Icon(Icons.notifications_none, color: widget.color),
      ),
    );
  }
}

String _ago(String? iso) {
  final t = DateTime.tryParse(iso ?? '')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${t.day}/${t.month}/${t.year}';
}

IconData _iconFor(Map n) {
  switch ((n['data'] as Map?)?['kind']) {
    case 'account_suspended':
    case 'shop_suspended':
      return Icons.block;
    case 'account_restored':
    case 'shop_restored':
      return Icons.check_circle_outline;
  }
  switch (n['type']) {
    case 'order': return Icons.receipt_long_outlined;
    case 'verification': return Icons.verified_outlined;
    case 'reward': return Icons.card_giftcard;
    default: return Icons.notifications_none;
  }
}

Color _tintFor(Map n) {
  final k = (n['data'] as Map?)?['kind'];
  if (k == 'account_suspended' || k == 'shop_suspended') return Colors.red.shade700;
  if (k == 'account_restored' || k == 'shop_restored') return MMColors.moss;
  return MMColors.deepOlive;
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _marked = false;

  Future<void> _markAllRead() async {
    try {
      await ApiClient.dio.post('/notifications/read', data: {});
      ref.invalidate(notificationsProvider);
    } catch (_) { /* not fatal */ }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/app'),
        ),
        title: Text(context.tr('Notifications')),
        actions: [TextButton(onPressed: _markAllRead, child: Text(context.tr('Mark all read')))],
      ),
      body: data.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(notificationsProvider)),
        data: (d) {
          final items = ((d['items'] as List?) ?? const []).whereType<Map>().toList();
          // Opening the screen counts as reading them (the unread dots stay visible this once).
          if (!_marked && (d['unread'] as num? ?? 0) > 0) {
            _marked = true;
            Future.delayed(const Duration(seconds: 2), () { if (mounted) _markAllRead(); });
          }
          if (items.isEmpty) return EmptyView(message: context.tr('No notifications yet.'));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final n = items[i];
                final unread = n['isRead'] != true;
                return Card(
                  color: unread ? MMColors.cream : Colors.white,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _tintFor(n).withOpacity(0.12),
                      child: Icon(_iconFor(n), color: _tintFor(n)),
                    ),
                    title: Text(n['title']?.toString() ?? '',
                        style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if ((n['body']?.toString() ?? '').isNotEmpty) Text(n['body'].toString()),
                        const SizedBox(height: 4),
                        Text(_ago(n['createdAt']?.toString()), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ]),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
