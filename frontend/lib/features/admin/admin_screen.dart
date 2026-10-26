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
  String _status = 'approved';

  Future<void> _review(String businessId, String action) async {
    String? reason;
    if (action == 'reject') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Rejection Reason', style: serif(18)),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Explain what information or correction is required...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
              ),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Reject Business'),
            ),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }
    try {
      await ApiClient.dio.post(
        '/admin/verifications/$businessId',
        data: {'action': action, if (reason != null) 'reason': reason},
      );
      ref.invalidate(adminBusinessesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'approve'
                  ? 'Business approved successfully'
                  : 'Business registration rejected',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e))),
        );
      }
    }
  }

  void _showBusinessDetails(Map<String, dynamic> b) {
    final owner = (b['owner'] as Map?) ?? {};
    final address = (b['address'] as Map?) ?? {};
    final rating = (b['rating'] as Map?) ?? {};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(b['name']?.toString() ?? 'Business Details', style: serif(18)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (b['description'] != null) ...[
                  Text(
                    b['description'].toString(),
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  const Divider(height: 24),
                ],
                _detailRow('Owner Name', owner['name']?.toString() ?? '-'),
                _detailRow('Email', owner['email']?.toString() ?? '-'),
                _detailRow('Category', b['category']?.toString() ?? '-'),
                _detailRow('Experience', '${b['yearsOfExperience'] ?? 0} years'),
                _detailRow(
                  'Address',
                  '${address['line1'] ?? ''}, ${address['city'] ?? ''} ${address['postalCode'] ?? ''}',
                ),
                _detailRow(
                  'Rating',
                  (rating['count'] ?? 0) == 0
                      ? 'No ratings yet'
                      : '★ ${rating['avg']} (${rating['count']} reviews)',
                ),
                _detailRow(
                  'Status',
                  (b['verification'] as Map?)?['status']?.toString().toUpperCase() ?? '-',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: MMColors.muted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isAdmin) {
      return Scaffold(
        backgroundColor: MMColors.paper,
        appBar: AppBar(title: const Text('Admin Portal')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 56, color: MMColors.muted),
                const SizedBox(height: 16),
                Text('Administrator Access Required', style: serif(20)),
                const SizedBox(height: 8),
                const Text(
                  'You must sign in with an account having administrator privileges to review sellers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MMColors.muted),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  onPressed: () => context.go('/login'),
                  label: const Text('Sign in as Admin'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final businesses = ref.watch(adminBusinessesProvider(_status));
    return Scaffold(
      backgroundColor: MMColors.paper,
      appBar: AppBar(
        title: Row(
          children: [
            Text('Seller Verifications', style: serif(18)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: MMColors.olive.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ADMIN',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MMColors.olive,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminBusinessesProvider),
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
      body: ResponsiveContainer(
        maxWidth: Breakpoints.desktop,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'approved',
                      label: Text('Verified'),
                      icon: Icon(Icons.check_circle_outline),
                    ),
                    ButtonSegment(
                      value: 'in_review',
                      label: Text('In Review'),
                      icon: Icon(Icons.hourglass_empty),
                    ),
                    ButtonSegment(
                      value: 'pending',
                      label: Text('Pending'),
                      icon: Icon(Icons.pending_actions),
                    ),
                    ButtonSegment(
                      value: 'rejected',
                      label: Text('Rejected'),
                      icon: Icon(Icons.cancel_outlined),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
              ),
            ),
            Expanded(
              child: businesses.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                  message: apiError(e),
                  onRetry: () => ref.invalidate(adminBusinessesProvider),
                ),
                data: (items) => items.isEmpty
                    ? Center(
                        child: EmptyView(
                          message: 'No sellers in $_status state.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final b = items[i];
                          final owner = (b['owner'] as Map?) ?? {};
                          final rating = (b['rating'] as Map?) ?? {};
                          final isApproved = _status == 'approved';
                          final needsAction =
                              _status == 'pending' || _status == 'in_review';

                          return Container(
                            decoration: BoxDecoration(
                              color: MMColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: MMColors.sand),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x06000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              onTap: () => _showBusinessDetails(b),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: NetImage(b['logoUrl']?.toString()),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      b['name']?.toString() ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (isApproved)
                                    const Icon(
                                      Icons.verified,
                                      size: 16,
                                      color: Color(0xFF2E7D32),
                                    ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Owner: ${owner['name'] ?? '-'} · Category: ${b['category'] ?? '-'}\n'
                                  '${(rating['count'] ?? 0) == 0 ? 'No ratings yet' : '★ ${rating['avg']} (${rating['count']} reviews)'}',
                                  style: const TextStyle(fontSize: 12, color: MMColors.muted),
                                ),
                              ),
                              trailing: needsAction
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: MMColors.olive,
                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                          ),
                                          onPressed: () => _review(
                                            b['_id'].toString(),
                                            'approve',
                                          ),
                                          child: const Text('Approve'),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(0xFFC62828),
                                            side: const BorderSide(color: Color(0xFFC62828)),
                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                          ),
                                          onPressed: () => _review(
                                            b['_id'].toString(),
                                            'reject',
                                          ),
                                          child: const Text('Reject'),
                                        ),
                                      ],
                                    )
                                  : (isApproved
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE8F5E9),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            (rating['count'] ?? 0) as num >= 5 &&
                                                    ((rating['avg'] ?? 0) as num) >= 4.5
                                                ? 'Top Seller'
                                                : 'Verified Seller',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2E7D32),
                                            ),
                                          ),
                                        )
                                      : null),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
