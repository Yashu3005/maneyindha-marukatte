import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

num _n(dynamic v) => v is num ? v : 0;

/// Statistics come straight from the server's live database queries; nothing here is estimated.
class AdminOverviewTab extends ConsumerWidget {
  const AdminOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    return stats.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(adminStatsProvider)),
      data: (s) {
        final users = (s['users'] as Map?) ?? const {};
        final shops = (s['shops'] as Map?) ?? const {};
        final orders = (s['orders'] as Map?) ?? const {};
        final reviews = (s['reviews'] as Map?) ?? const {};
        final coupons = (s['coupons'] as Map?) ?? const {};
        final top = ((shops['topByRevenue'] as List?) ?? const []).cast<Map>();
        final recent = ((orders['recent'] as List?) ?? const []).cast<Map>();
        final byStatus = ((orders['byStatus'] as Map?) ?? const {}).entries.toList();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _Section('Members'),
              _Grid([
                _Tile('Customers', '${_n(users['customers'])}', Icons.people_outline),
                _Tile('Entrepreneurs', '${_n(users['entrepreneurs'])}', Icons.storefront_outlined),
                _Tile('Delivery partners', '${_n(users['deliveryPartners'])}', Icons.delivery_dining_outlined),
                _Tile('Joined (7 days)', '${_n(users['newLast7Days'])}', Icons.person_add_alt_outlined),
              ]),
              _ChartCard(title: 'New members · last 14 days', days: (users['signupsByDay'] as List?) ?? const [], field: 'count'),
              _Section('Shops'),
              _Grid([
                _Tile('Verified', '${_n(shops['approved'])}', Icons.verified_outlined),
                _Tile('Awaiting review', '${_n(shops['inReview'])}', Icons.hourglass_top_outlined,
                    highlight: _n(shops['inReview']) > 0),
                _Tile('Open now', '${_n(shops['openNow'])}', Icons.door_front_door_outlined),
                _Tile('With video', '${_n(shops['withPromoVideo'])}', Icons.ondemand_video_outlined),
              ]),
              _Section('Orders & revenue'),
              _Grid([
                _Tile('Orders today', '${_n(orders['today'])}', Icons.today_outlined),
                _Tile('Active now', '${_n(orders['active'])}', Icons.local_shipping_outlined),
                _Tile('Delivered', '${_n(orders['delivered'])}', Icons.check_circle_outline),
                _Tile('Cancelled', '${_n(orders['cancelled'])}', Icons.cancel_outlined),
                _Tile('Revenue (delivered)', rupees(_n(orders['revenueDelivered'])), Icons.currency_rupee),
                _Tile('Avg order value', rupees(_n(orders['averageOrderValue'])), Icons.receipt_long_outlined),
                if (_n(orders['needsRefund']) > 0)
                  _Tile('Need refund', '${_n(orders['needsRefund'])}', Icons.undo, highlight: true),
              ]),
              _ChartCard(title: 'Orders · last 14 days', days: (orders['byDay'] as List?) ?? const [], field: 'count'),
              _ChartCard(
                  title: 'Delivered revenue (₹) · last 14 days',
                  days: (orders['byDay'] as List?) ?? const [],
                  field: 'revenue'),
              if (byStatus.isNotEmpty) ...[
                _Section('Orders by status'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in byStatus) Chip(label: Text('${e.key}: ${e.value}')),
                ]),
              ],
              _Section('Reviews & coupons'),
              _Grid([
                _Tile('Reviews', '${_n(reviews['count'])}', Icons.rate_review_outlined),
                _Tile('Average rating', _n(reviews['count']) == 0 ? '—' : '${_n(reviews['average'])}', Icons.star_outline_rounded),
                _Tile('Coupons active', '${_n(coupons['active'])}', Icons.local_offer_outlined),
                _Tile('Coupons used', '${_n(coupons['redeemed'])}', Icons.confirmation_number_outlined),
              ]),
              if (top.isNotEmpty) ...[
                _Section('Top shops by delivered revenue'),
                for (final t in top)
                  ListTile(
                    dense: true,
                    title: Text(t['name']?.toString() ?? ''),
                    subtitle: Text('${_n(t['orders'])} delivered orders'),
                    trailing: Text(rupees(_n(t['revenue'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
              if (recent.isNotEmpty) ...[
                _Section('Recent orders'),
                for (final o in recent)
                  ListTile(
                    dense: true,
                    title: Text('${o['orderNumber'] ?? ''} · ${o['shop'] ?? ''}'),
                    subtitle: Text('${o['status']} · ${o['method'] ?? ''}'),
                    trailing: Text(rupees(_n(o['total']))),
                  ),
              ],
              const SizedBox(height: 8),
              Text('Live from the database · generated ${s['generatedAt'] ?? ''}',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(0, 22, 0, 10), child: Text(text, style: serif(20)));
}

class _Tile {
  final String label, value;
  final IconData icon;
  final bool highlight;
  _Tile(this.label, this.value, this.icon, {this.highlight = false});
}

class _Grid extends StatelessWidget {
  final List<_Tile> tiles;
  const _Grid(this.tiles);

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final t in tiles)
        SizedBox(
          width: 200,
          child: SoftCard(
            child: Row(children: [
              Icon(t.icon, color: t.highlight ? MMColors.clay : MMColors.moss),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.value, style: t.highlight ? serif(20, color: MMColors.clay) : serif(20)),
                  Text(t.label, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List days;
  final String field;
  const _ChartCard({required this.title, required this.days, required this.field});

  @override
  Widget build(BuildContext context) {
    final values = [for (final d in days) _n((d as Map)[field]).toDouble()];
    final labels = [for (final d in days) ((d as Map)['date']?.toString() ?? '').split('-').skip(1).join('/')];
    final total = values.fold<double>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('Total ${total.round()}', style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 130,
            width: double.infinity,
            child: values.isEmpty || total == 0
                ? Center(child: Text('No activity yet', style: Theme.of(context).textTheme.bodySmall))
                : CustomPaint(painter: _BarPainter(values, labels)),
          ),
        ]),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  _BarPainter(this.values, this.labels);

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 16.0;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final chartH = size.height - labelH;
    final slot = size.width / values.length;
    final barW = slot * 0.6;
    final paint = Paint()..color = MMColors.moss;
    for (var i = 0; i < values.length; i++) {
      final h = maxV == 0 ? 0.0 : (values[i] / maxV) * (chartH - 14);
      final x = i * slot + (slot - barW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, chartH - h, barW, h), const Radius.circular(3)),
        paint,
      );
      if (values[i] > 0) _text(canvas, values[i].round().toString(), Offset(i * slot + slot / 2, chartH - h - 12), 9, MMColors.deepOlive);
      if (i % 2 == 0 || values.length < 8) {
        _text(canvas, labels[i], Offset(i * slot + slot / 2, chartH + 3), 9, Colors.black54);
      }
    }
  }

  void _text(Canvas c, String t, Offset centre, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(centre.dx - tp.width / 2, centre.dy));
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.values != values || old.labels != labels;
}

/// Members list with suspend / restore. The administrator is never listed.
class AdminMembersTab extends ConsumerStatefulWidget {
  const AdminMembersTab({super.key});
  @override
  ConsumerState<AdminMembersTab> createState() => _AdminMembersTabState();
}

class _AdminMembersTabState extends ConsumerState<AdminMembersTab> {
  String _role = '';
  final _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _toggle(Map u) async {
    final suspend = u['isActive'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(suspend ? 'Suspend this member?' : 'Restore this member?'),
        content: Text(suspend
            ? '${u['name'] ?? 'This member'} will be signed out and unable to sign in until restored.'
            : '${u['name'] ?? 'This member'} will be able to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(suspend ? 'Suspend' : 'Restore')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.dio.patch('/admin/users/${u['_id']}/status', data: {'isActive': !suspend});
      ref.invalidate(adminUsersProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider('$_role|$_query'));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search name or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() { _q.clear(); _query = ''; }),
                      ),
              ),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '', label: Text('All')),
              ButtonSegment(value: 'customer', label: Text('Customers')),
              ButtonSegment(value: 'entrepreneur', label: Text('Entrepreneurs')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: users.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(adminUsersProvider)),
              data: (items) => items.isEmpty
                  ? const EmptyView(message: 'No members found.')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final u = items[i];
                        final active = u['isActive'] != false;
                        return ListTile(
                          title: Text(u['name']?.toString() ?? '(no name)'),
                          subtitle: Text('${u['email'] ?? ''} · ${u['role']}'),
                          trailing: active
                              ? OutlinedButton(onPressed: () => _toggle(u), child: const Text('Suspend'))
                              : FilledButton.tonal(onPressed: () => _toggle(u), child: const Text('Restore')),
                        );
                      },
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
