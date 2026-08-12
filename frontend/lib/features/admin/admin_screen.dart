import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  String _status = 'approved';

  Future<void> _review(String businessId, String action) async {
    String? reason;
    if (action == 'reject') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rejection reason'),
          content: TextField(controller: controller, maxLines: 2),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Reject')),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }
    try {
      await ApiClient.dio.post('/admin/verifications/$businessId',
          data: {'action': action, if (reason != null) 'reason': reason});
      ref.invalidate(adminBusinessesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(action == 'approve' ? 'Approved' : 'Rejected')));
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
    if (!auth.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Sign in as admin'),
          ),
        ),
      );
    }

    final businesses = ref.watch(adminBusinessesProvider(_status));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrepreneurs'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'approved', label: Text('Verified')),
              ButtonSegment(value: 'in_review', label: Text('In review')),
              ButtonSegment(value: 'pending', label: Text('Pending')),
              ButtonSegment(value: 'rejected', label: Text('Rejected')),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
        ),
        Expanded(
          child: businesses.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
                message: apiError(e),
                onRetry: () => ref.invalidate(adminBusinessesProvider)),
            data: (items) => items.isEmpty
                ? const EmptyView(message: 'Nothing here.')
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final b = items[i];
                          final owner = (b['owner'] as Map?) ?? {};
                          final rating = (b['rating'] as Map?) ?? {};
                          final isApproved = _status == 'approved';
                          final needsAction =
                              _status == 'pending' || _status == 'in_review';
                          return Card(
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(width: 48, height: 48,
                                    child: NetImage(b['logoUrl']?.toString())),
                              ),
                              title: Row(children: [
                                Flexible(child: Text(b['name']?.toString() ?? '')),
                                const SizedBox(width: 6),
                                if (isApproved)
                                  Icon(Icons.verified,
                                      size: 18,
                                      color: Theme.of(context).colorScheme.primary),
                              ]),
                              subtitle: Text('${owner['name'] ?? '-'} · '
                                  '${(rating['count'] ?? 0) == 0 ? 'No ratings yet' : '★ ${rating['avg']} (${rating['count']} reviews)'}'),
                              trailing: needsAction
                                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                                      FilledButton(
                                        onPressed: () =>
                                            _review(b['_id'].toString(), 'approve'),
                                        child: const Text('Approve'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: () =>
                                            _review(b['_id'].toString(), 'reject'),
                                        child: const Text('Reject'),
                                      ),
                                    ])
                                  : (isApproved
                                      ? Chip(
                                          label: Text(
                                              (rating['count'] ?? 0) as num >= 5 &&
                                                      ((rating['avg'] ?? 0) as num) >= 4.5
                                                  ? 'Top Seller'
                                                  : 'Verified Seller'),
                                        )
                                      : null),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}
