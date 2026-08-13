import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  String _status = 'in_review';

  Future<void> _review(String businessId, String action) async {
    String? reason;
    if (action != 'approve') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(action == 'reject' ? 'Rejection reason' : 'What information is needed?'),
          content: TextField(controller: controller, maxLines: 2),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Send')),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }
    try {
      await ApiClient.dio.post('/admin/verifications/$businessId',
          data: {'action': action, if (reason != null) 'reason': reason});
      ref.invalidate(adminBusinessesProvider);
      ref.invalidate(adminStatsProvider);
      if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _blockOwner(String userId, bool block) async {
    try {
      await ApiClient.dio.patch('/admin/users/$userId/active', data: {'isActive': !block});
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(block ? 'Account blocked' : 'Account unblocked')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  void _openDetails(Map<String, dynamic> b) {
    final owner = (b['owner'] as Map?) ?? {};
    final verification = (b['verification'] as Map?) ?? {};
    final docs = (verification['documents'] as List?) ?? [];
    final rating = (b['rating'] as Map?) ?? {};
    final address = (b['address'] as Map?) ?? {};
    final status = verification['status']?.toString() ?? 'pending';
    final needsAction = status == 'pending' || status == 'in_review';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 56, height: 56,
                    child: NetImage(b['logoUrl']?.toString())),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b['name']?.toString() ?? '', style: serif(20)),
                  Text('Status: ${status.replaceAll('_', ' ')}'),
                ]),
              ),
              _badge(rating, status),
            ]),
            const Divider(height: 24),
            Text('Owner', style: serif(15)),
            Text('${owner['name'] ?? '-'} · ${owner['email'] ?? '-'} · ${owner['phone'] ?? 'no phone'}'),
            const SizedBox(height: 10),
            Text('Business', style: serif(15)),
            Text('${b['description'] ?? '-'}'),
            Text('Experience: ${b['yearsOfExperience'] ?? '-'} · '
                '${address['line1'] ?? '-'}, ${address['city'] ?? ''}'),
            Text('Rating: ${(rating['count'] ?? 0) == 0 ? 'no reviews yet' : '★ ${rating['avg']} from ${rating['count']} reviews'}'),
            const SizedBox(height: 14),
            Text('Verification documents (${docs.length})', style: serif(15)),
            const SizedBox(height: 8),
            if (docs.isEmpty)
              const Text('No documents submitted yet.')
            else
              Wrap(
                spacing: 10, runSpacing: 10,
                children: docs.map((raw) {
                  final d = Map<String, dynamic>.from(raw as Map);
                  final label = d['identityType']?.toString() ??
                      d['type'].toString().replaceAll('_', ' ');
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: () => showDialog(
                        context: ctx,
                        builder: (_) => Dialog(
                            child: InteractiveViewer(
                                child: Image.network(d['url'].toString()))),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(d['url'].toString(),
                            width: 140, height: 100, fit: BoxFit.cover),
                      ),
                    ),
                    Text(label, style: const TextStyle(fontSize: 12)),
                  ]);
                }).toList(),
              ),
            const SizedBox(height: 18),
            if (needsAction)
              Row(children: [
                FilledButton(
                    onPressed: () => _review(b['_id'].toString(), 'approve'),
                    child: const Text('Approve')),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: () => _review(b['_id'].toString(), 'reject'),
                    child: const Text('Reject')),
                const SizedBox(width: 8),
                TextButton(
                    onPressed: () => _review(b['_id'].toString(), 'request_info'),
                    child: const Text('Request info')),
              ]),
            const SizedBox(height: 6),
            Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Block owner account'),
                onPressed: owner['_id'] == null
                    ? null
                    : () => _blockOwner(owner['_id'].toString(), true),
              ),
              TextButton(
                onPressed: owner['_id'] == null
                    ? null
                    : () => _blockOwner(owner['_id'].toString(), false),
                child: const Text('Unblock'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _badge(Map rating, String status) {
    if (status != 'approved') return const SizedBox.shrink();
    final count = (rating['count'] ?? 0) as num;
    final avg = (rating['avg'] ?? 0) as num;
    final top = count >= 5 && avg >= 4.5;
    return Chip(
      avatar: Icon(top ? Icons.emoji_events : Icons.verified,
          size: 16, color: top ? MMColors.marigold : MMColors.deepOlive),
      label: Text(top ? 'Top Seller' : 'Verified Seller'),
    );
  }

  Widget _statCard(String label, String value) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Text(value, style: serif(20)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

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

    final stats = ref.watch(adminStatsProvider);
    final businesses = ref.watch(adminBusinessesProvider(_status));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Entrepreneurs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(adminStatsProvider);
              ref.invalidate(adminBusinessesProvider);
            },
          ),
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
        stats.when(
          loading: () => const SizedBox(height: 8),
          error: (e, _) => const SizedBox(height: 8),
          data: (s) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              _statCard('Customers', '${s['customers']}'),
              const SizedBox(width: 8),
              _statCard('Entrepreneurs', '${s['entrepreneurs']}'),
              const SizedBox(width: 8),
              _statCard('Shops (approved)', '${s['approved']}/${s['businesses']}'),
              const SizedBox(width: 8),
              _statCard('Orders', '${s['orders']}'),
              const SizedBox(width: 8),
              _statCard('Revenue', rupees(s['revenue'])),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'in_review', label: Text('In review')),
              ButtonSegment(value: 'pending', label: Text('Pending')),
              ButtonSegment(value: 'approved', label: Text('Verified')),
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
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final b = items[i];
                          final owner = (b['owner'] as Map?) ?? {};
                          final rating = (b['rating'] as Map?) ?? {};
                          final verification = (b['verification'] as Map?) ?? {};
                          final docs = (verification['documents'] as List?) ?? [];
                          return Card(
                            child: ListTile(
                              onTap: () => _openDetails(b),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(width: 48, height: 48,
                                    child: NetImage(b['logoUrl']?.toString())),
                              ),
                              title: Text(b['name']?.toString() ?? ''),
                              subtitle: Text(
                                  '${owner['name'] ?? '-'} · ${owner['email'] ?? ''}\n'
                                  '${(rating['count'] ?? 0) == 0 ? 'No ratings yet' : '★ ${rating['avg']} (${rating['count']})'}'
                                  ' · ${docs.length} document${docs.length == 1 ? '' : 's'}'),
                              isThreeLine: true,
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                _badge(rating, _status),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right),
                              ]),
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
