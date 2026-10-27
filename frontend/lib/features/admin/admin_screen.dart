import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import 'admin_dashboard.dart';

/// Applications tab: documents + approve/reject. Only submitted (in_review) applications can be approved.
class ApplicationsTab extends ConsumerStatefulWidget {
  const ApplicationsTab({super.key});
  @override
  ConsumerState<ApplicationsTab> createState() => _ApplicationsTabState();
}

class _ApplicationsTabState extends ConsumerState<ApplicationsTab> {
  String _status = 'in_review';

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
      ref.invalidate(adminStatsProvider);
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

  static const _docLabels = {
    'id_proof': 'ID proof',
    'business_proof': 'Business proof',
    'address_proof': 'Address proof',
    'other': 'Other document',
  };

  /// Documents are private: each open asks the server for a link that expires in a few minutes.
  Future<void> _openDoc(String businessId, String docId) async {
    try {
      final res = await ApiClient.dio.get('/admin/verifications/$businessId/documents/$docId/link');
      final url = res.data['data']['url']?.toString();
      if (url == null || url.isEmpty) throw Exception('no link');
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _viewDocs(Map<String, dynamic> b) async {
    final docs = (((b['verification'] as Map?)?['documents']) as List?) ?? const [];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${b['name'] ?? 'Shop'} · documents'),
        content: SizedBox(
          width: 420,
          child: docs.isEmpty
              ? const Text('No documents uploaded.')
              : Column(mainAxisSize: MainAxisSize.min, children: docs.map((raw) {
                  final d = Map<String, dynamic>.from(raw as Map);
                  final label = _docLabels[d['type']] ?? d['type'].toString();
                  final idType = d['identityType'] != null ? ' (${d['identityType']})' : '';
                  return ListTile(
                    dense: true,
                    leading: Icon(d['mime'] == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                    title: Text('$label$idType'),
                    subtitle: Text(d['originalName']?.toString() ?? ''),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: d['_id'] == null ? null : () => _openDoc(b['_id'].toString(), d['_id'].toString()),
                  );
                }).toList()),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final businesses = ref.watch(adminBusinessesProvider(_status));
    return Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'in_review', label: Text('Submitted')),
              ButtonSegment(value: 'approved', label: Text('Verified')),
              ButtonSegment(value: 'pending', label: Text('Not submitted')),
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
                          final needsAction = _status == 'in_review';
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
                                      TextButton.icon(
                                        onPressed: () => _viewDocs(Map<String, dynamic>.from(b)),
                                        icon: const Icon(Icons.folder_open, size: 18),
                                        label: const Text('Documents'),
                                      ),
                                      const SizedBox(width: 8),
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
                                  : _status == 'pending'
                                  ? const Chip(label: Text('Waiting for documents'))
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
    ]);
  }
}

/// Admin console: overview statistics, applications, and members. Only the one configured administrator gets in.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn || !auth.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/admin/login'),
            child: const Text('Administrator sign in'),
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administrator'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(adminStatsProvider);
                ref.invalidate(adminBusinessesProvider);
                ref.invalidate(adminUsersProvider);
              },
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/');
              },
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Applications'),
            Tab(text: 'Members'),
          ]),
        ),
        body: const TabBarView(children: [
          AdminOverviewTab(),
          ApplicationsTab(),
          AdminMembersTab(),
        ]),
      ),
    );
  }
}
