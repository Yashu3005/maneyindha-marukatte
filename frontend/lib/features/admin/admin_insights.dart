import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import 'admin_style.dart';

// Growth, Owners, Shops, Products and Badges for the administrator. Everything shown is read from the server's live
// queries (see /admin/growth, /admin/owners, ...); nothing is estimated here.

num _n(dynamic v) => v is num ? v : 0;
String _s(dynamic v) => v?.toString() ?? '';
List<Map> _list(dynamic v) => v is List ? v.whereType<Map>().toList() : <Map>[];
Map _map(dynamic v) => v is Map ? v : const {};
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _monthLabel(String ym) {
  final p = ym.split('-');
  if (p.length < 2) return ym;
  final m = (int.tryParse(p[1]) ?? 1).clamp(1, 12).toInt();
  return _mon[m - 1];
}

String _initial(String name) => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
String _date(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  return t == null ? '' : '${t.day} ${_mon[t.month - 1]} ${t.year}';
}

Widget _page(Widget child) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: child));

// =====================================================================================================
// Growth
// =====================================================================================================
class AdminGrowthTab extends ConsumerStatefulWidget {
  const AdminGrowthTab({super.key});
  @override
  ConsumerState<AdminGrowthTab> createState() => _AdminGrowthTabState();
}

class _AdminGrowthTabState extends ConsumerState<AdminGrowthTab> {
  int _months = 6;
  String _metric = 'orders';
  static const _metrics = {
    'orders': 'Orders',
    'revenue': 'Revenue (₹)',
    'customers': 'New customers',
    'entrepreneurs': 'New entrepreneurs',
    'shops': 'New shops',
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(adminMapProvider(adminUrl('/admin/growth', {'months': '$_months'})));
    return Container(
      color: kAdminBg,
      child: data.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(adminMapProvider)),
        data: (d) {
          final series = _list(d['series']);
          final cur = _map(d['thisMonth']);
          final change = _map(d['change']);
          final totals = _map(d['totals']);
          final values = [for (final r in series) _n(r[_metric]).toDouble()];
          final labels = [for (final r in series) _monthLabel(_s(r['month']))];
          double? pct(String k) => change[k] is num ? (change[k] as num).toDouble() : null;
          double share(num a, num b) => b <= 0 ? 0.0 : (a / b).toDouble();
          final members = _n(totals['customers']) + _n(totals['entrepreneurs']);
          return _page(ListView(padding: const EdgeInsets.all(16), children: [
            Reveal(
              index: 0,
              child: HeroCard(
                title: 'This month so far · ${_monthLabel(_s(cur['month']))}',
                child: Wrap(spacing: 24, runSpacing: 16, children: [
                  _HeroStat('Orders', _n(cur['orders']), (v) => '${v.round()}', pct('orders')),
                  _HeroStat('Revenue', _n(cur['revenue']), (v) => rupees(v.round()), pct('revenue')),
                  _HeroStat('New customers', _n(cur['customers']), (v) => '${v.round()}', pct('customers')),
                  _HeroStat('New entrepreneurs', _n(cur['entrepreneurs']), (v) => '${v.round()}', pct('entrepreneurs')),
                  _HeroStat('New shops', _n(cur['shops']), (v) => '${v.round()}', pct('shops')),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            Reveal(
              index: 1,
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final e in _metrics.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _metric == e.key,
                    onSelected: (_) => setState(() => _metric = e.key),
                  ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 6, label: Text('6 months')),
                    ButtonSegment(value: 12, label: Text('12 months')),
                  ],
                  selected: {_months},
                  onSelectionChanged: (s) => setState(() => _months = s.first),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Reveal(
              index: 2,
              child: LineChartCard(
                title: _metrics[_metric] ?? '',
                trailing: 'last $_months months',
                values: values,
                labels: labels,
                color: _metric == 'revenue' ? MMColors.clay : MMColors.moss,
              ),
            ),
            Reveal(
              index: 3,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _RingTile('Shops verified', share(_n(totals['approvedShops']), _n(totals['shops'])), MMColors.moss)),
                const SizedBox(width: 10),
                Expanded(child: _RingTile('Orders delivered', share(_n(totals['deliveredOrders']), _n(totals['orders'])), MMColors.marigold)),
                const SizedBox(width: 10),
                Expanded(child: _RingTile('Members who sell', share(_n(totals['entrepreneurs']), members), MMColors.clay)),
              ]),
            ),
            Reveal(
              index: 4,
              child: Wrap(spacing: 10, runSpacing: 0, children: [
                _TotalTile('Customers', '${_n(totals['customers'])}', Icons.people_outline),
                _TotalTile('Entrepreneurs', '${_n(totals['entrepreneurs'])}', Icons.storefront_outlined),
                _TotalTile('Shops', '${_n(totals['shops'])}', Icons.store_mall_directory_outlined),
                _TotalTile('Products', '${_n(totals['products'])}', Icons.inventory_2_outlined),
                _TotalTile('Orders', '${_n(totals['orders'])}', Icons.receipt_long_outlined),
                _TotalTile('Revenue (delivered)', rupees(_n(totals['revenue'])), Icons.currency_rupee),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('Live from the database. Percentages compare this month with last month.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12)),
          ]));
        },
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final num value;
  final String Function(num) format;
  final double? pct;
  const _HeroStat(this.label, this.value, this.format, this.pct);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 2),
        CountUp(value: value, format: format, style: serif(24, color: Colors.white)),
        const SizedBox(height: 2),
        DeltaChip(pct),
      ]),
    );
  }
}

class _RingTile extends StatelessWidget {
  final String label;
  final double fraction;
  final Color color;
  const _RingTile(this.label, this.fraction, this.color);

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(children: [
        Ring(
          fraction: fraction,
          color: color,
          center: Text('${(fraction * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ]),
    );
  }
}

class _TotalTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _TotalTile(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: AdminCard(
        child: Row(children: [
          Icon(icon, color: MMColors.moss),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: serif(19)),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =====================================================================================================
// Owners
// =====================================================================================================
class AdminOwnersTab extends ConsumerStatefulWidget {
  const AdminOwnersTab({super.key});
  @override
  ConsumerState<AdminOwnersTab> createState() => _AdminOwnersTabState();
}

class _AdminOwnersTabState extends ConsumerState<AdminOwnersTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminListProvider(adminUrl('/admin/owners', {'q': _q, 'limit': '50'})));
    return Container(
      color: kAdminBg,
      child: _page(Column(children: [
        AdminSearchField(hint: 'Search owner name or email', onSearch: (v) => setState(() => _q = v)),
        Expanded(
          child: list.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(adminListProvider)),
            data: (items) => items.isEmpty
                ? const EmptyView(message: 'No shop owners found.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: items.length,
                    itemBuilder: (_, i) => Reveal(index: i, child: _OwnerCard(items[i])),
                  ),
          ),
        ),
      ])),
    );
  }
}

class _OwnerCard extends StatelessWidget {
  final Map<String, dynamic> o;
  const _OwnerCard(this.o);

  @override
  Widget build(BuildContext context) {
    final badge = _map(o['badge']);
    final rating = _map(o['rating']);
    final active = o['isActive'] != false;
    return AdminCard(
      onTap: () => showOwnerDetail(context, _s(o['id'])),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 24, backgroundColor: MMColors.sage, child: Text(_initial(_s(o['name'])), style: serif(18))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_s(o['name']).isEmpty ? '(no name)' : _s(o['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(_s(o['email']), style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusPill('${_s(badge['icon'])} ${_s(badge['label'])}', color: MMColors.deepOlive),
              StatusPill('${_n(o['shops'])} shop${_n(o['shops']) == 1 ? '' : 's'}', color: Colors.blueGrey),
              StatusPill('${_n(o['delivered'])} delivered', color: MMColors.moss),
              StatusPill(rupees(_n(o['revenue'])), color: MMColors.clay),
              if (!active) StatusPill('Suspended', color: Colors.red.shade700),
            ]),
          ]),
        ),
        Column(children: [
          const Icon(Icons.star_rounded, color: MMColors.marigold, size: 20),
          Text(_n(rating['count']) == 0 ? '—' : '${rating['avg']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

void showOwnerDetail(BuildContext context, String id) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kAdminBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _OwnerDetail(id: id),
  );
}

class _OwnerDetail extends ConsumerWidget {
  final String id;
  const _OwnerDetail({required this.id});

  Future<void> _toggleAccount(BuildContext context, WidgetRef ref, Map owner) async {
    final suspend = owner['isActive'] != false;
    final reason = await showReasonDialog(
      context,
      title: suspend ? 'Suspend this account?' : 'Restore this account?',
      message: suspend
          ? '${_s(owner['name'])} is signed out, cannot sign in, and their shops are hidden from customers. They are told by email and in the app.'
          : '${_s(owner['name'])} can sign in again and their hidden shops come back. They are told by email and in the app.',
      needReason: suspend,
      confirmLabel: suspend ? 'Suspend' : 'Restore',
    );
    if (reason == null) return;
    try {
      await ApiClient.dio.patch('/admin/users/${owner['id']}/status', data: {'isActive': !suspend, if (suspend) 'reason': reason});
      ref.read(adminRefreshProvider.notifier).state++;
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminMapProvider('/admin/owners/$id'));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: data.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(adminMapProvider)),
        data: (d) {
          final owner = _map(d['owner']);
          final summary = _map(d['summary']);
          final badges = _map(d['badges']);
          final badge = _map(badges['badge']);
          final next = badges['next'] is Map ? _map(badges['next']) : null;
          final rating = _map(summary['rating']);
          final shops = _list(d['shops']);
          final monthly = _list(d['monthly']);
          final active = owner['isActive'] != false;
          return _page(ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              CircleAvatar(radius: 28, backgroundColor: MMColors.sage, child: Text(_initial(_s(owner['name'])), style: serif(22))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_s(owner['name']), style: serif(20)),
                  Text(_s(owner['email']), style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  if (_s(owner['phone']).isNotEmpty) Text(_s(owner['phone']), style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  Text('Joined ${_date(_s(owner['joinedAt']))}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            if (!active) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                child: Text('Account suspended. Reason: ${_s(owner['suspensionReason']).isEmpty ? 'not given' : _s(owner['suspensionReason'])}',
                    style: TextStyle(color: Colors.red.shade900)),
              ),
            ],
            const SizedBox(height: 16),
            HeroCard(
              title: 'Badge',
              child: Row(children: [
                Text(_s(badge['icon']), style: const TextStyle(fontSize: 44)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_s(badge['label']), style: serif(20, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(_s(badge['blurb']), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    if (next != null) ...[
                      const SizedBox(height: 6),
                      Text('${_n(next['ordersToGo'])} more delivered orders to ${_s(next['label'])}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in _list(badges['badges']))
                StatusPill(
                  '${b['earned'] == true ? '✓ ' : ''}${_s(b['icon'])} ${_s(b['label'])} · ${_n(b['min'])}+',
                  color: b['earned'] == true ? MMColors.moss : Colors.grey,
                ),
            ]),
            const SizedBox(height: 10),
            for (final a in _list(badges['achievements']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Text(_s(a['icon']), style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${_s(a['label'])} — ${_s(a['hint'])}', style: const TextStyle(fontSize: 13))),
                  Icon(a['earned'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: a['earned'] == true ? MMColors.moss : Colors.grey, size: 20),
                ]),
              ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _TotalTile('Delivered orders', '${_n(summary['delivered'])}', Icons.check_circle_outline)),
              const SizedBox(width: 10),
              Expanded(child: _TotalTile('Revenue', rupees(_n(summary['revenue'])), Icons.currency_rupee)),
              const SizedBox(width: 10),
              Expanded(child: _TotalTile('Rating', _n(rating['count']) == 0 ? '—' : '${rating['avg']} (${_n(rating['count'])})', Icons.star_outline_rounded)),
            ]),
            LineChartCard(
              title: 'Orders · last 6 months',
              trailing: 'Revenue ${rupees(monthly.fold<num>(0, (a, r) => a + _n(r['revenue'])))}',
              values: [for (final r in monthly) _n(r['count']).toDouble()],
              labels: [for (final r in monthly) _monthLabel(_s(r['month']))],
            ),
            const SizedBox(height: 6),
            Text('Shops (${shops.length})', style: serif(17)),
            const SizedBox(height: 8),
            for (final s in shops)
              AdminCard(
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: NetImage(_s(s['coverUrl']).isEmpty ? null : _s(s['coverUrl']), width: 56, height: 56)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_s(s['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        StatusPill(_s(s['status']).replaceAll('_', ' '), color: s['status'] == 'approved' ? MMColors.moss : MMColors.marigold),
                        if (s['isActive'] == false) StatusPill('Hidden', color: Colors.red.shade700),
                      ]),
                      const SizedBox(height: 4),
                      Text('${_n(s['products'])} products · ${_n(s['delivered'])} delivered · ${rupees(_n(s['revenue']))}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            active
                ? OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                    onPressed: () => _toggleAccount(context, ref, owner),
                    icon: const Icon(Icons.block),
                    label: const Text('Suspend this account'),
                  )
                : FilledButton.icon(
                    onPressed: () => _toggleAccount(context, ref, owner),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore this account'),
                  ),
            const SizedBox(height: 24),
          ]));
        },
      ),
    );
  }
}

// =====================================================================================================
// Shops
// =====================================================================================================
class AdminShopsTab extends ConsumerStatefulWidget {
  const AdminShopsTab({super.key});
  @override
  ConsumerState<AdminShopsTab> createState() => _AdminShopsTabState();
}

class _AdminShopsTabState extends ConsumerState<AdminShopsTab> {
  String _q = '';
  String _status = '';
  static const _filters = {
    '': 'All', 'approved': 'Approved', 'in_review': 'In review', 'pending': 'Pending', 'rejected': 'Rejected', 'suspended': 'Suspended',
  };

  Future<void> _toggle(Map shop) async {
    final suspend = shop['isActive'] != false;
    final reason = await showReasonDialog(
      context,
      title: suspend ? 'Suspend this shop?' : 'Restore this shop?',
      message: suspend
          ? '${_s(shop['name'])} is hidden from customers. Its owner is told by email and in the app.'
          : '${_s(shop['name'])} is visible to customers again. Its owner is told by email and in the app.',
      needReason: suspend,
      confirmLabel: suspend ? 'Suspend' : 'Restore',
    );
    if (reason == null) return;
    try {
      await ApiClient.dio.patch('/admin/businesses/${shop['id']}/status', data: {'isActive': !suspend, if (suspend) 'reason': reason});
      ref.read(adminRefreshProvider.notifier).state++;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminListProvider(adminUrl('/admin/shops', {'q': _q, 'status': _status, 'limit': '50'})));
    return Container(
      color: kAdminBg,
      child: _page(Column(children: [
        AdminSearchField(hint: 'Search shop name', onSearch: (v) => setState(() => _q = v)),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final e in _filters.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => setState(() => _status = e.key)),
              ),
          ]),
        ),
        Expanded(
          child: list.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(adminListProvider)),
            data: (items) => items.isEmpty
                ? const EmptyView(message: 'No shops found.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final s = items[i];
                      final rating = _map(s['rating']);
                      final owner = _map(s['owner']);
                      final active = s['isActive'] != false;
                      final susp = _map(s['suspension']);
                      return Reveal(
                        index: i,
                        child: AdminCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: NetImage(_s(s['coverUrl']).isEmpty ? null : _s(s['coverUrl']), width: 64, height: 64),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(_s(s['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                  Text('by ${_s(owner['name'])}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 6, runSpacing: 4, children: [
                                    StatusPill(_s(s['status']).replaceAll('_', ' '), color: s['status'] == 'approved' ? MMColors.moss : MMColors.marigold),
                                    if (!active) StatusPill(susp['byOwner'] == true ? 'Owner suspended' : 'Suspended', color: Colors.red.shade700),
                                    StatusPill(_n(rating['count']) == 0 ? 'No ratings' : '★ ${rating['avg']} (${_n(rating['count'])})', color: MMColors.marigold),
                                  ]),
                                ]),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Text('${_n(s['products'])} products · ${_n(s['delivered'])} delivered · ${rupees(_n(s['revenue']))}',
                                style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            if (!active && _s(susp['reason']).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Reason: ${_s(susp['reason'])}', style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: active
                                  ? TextButton.icon(
                                      style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                                      onPressed: () => _toggle(s),
                                      icon: const Icon(Icons.block, size: 18),
                                      label: const Text('Suspend'),
                                    )
                                  : FilledButton.tonalIcon(
                                      onPressed: () => _toggle(s),
                                      icon: const Icon(Icons.restore, size: 18),
                                      label: const Text('Restore'),
                                    ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ])),
    );
  }
}

// =====================================================================================================
// Products
// =====================================================================================================
class AdminProductsTab extends ConsumerStatefulWidget {
  const AdminProductsTab({super.key});
  @override
  ConsumerState<AdminProductsTab> createState() => _AdminProductsTabState();
}

class _AdminProductsTabState extends ConsumerState<AdminProductsTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminListProvider(adminUrl('/admin/products', {'q': _q, 'limit': '50'})));
    return Container(
      color: kAdminBg,
      child: _page(Column(children: [
        AdminSearchField(hint: 'Search product name', onSearch: (v) => setState(() => _q = v)),
        Expanded(
          child: list.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(adminListProvider)),
            data: (items) => items.isEmpty
                ? const EmptyView(message: 'No products found.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final p = items[i];
                      final shop = _map(p['shop']);
                      return Reveal(
                        index: i,
                        child: AdminCard(
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: NetImage(_s(p['imageUrl']).isEmpty ? null : _s(p['imageUrl']), width: 60, height: 60),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_s(p['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(_s(shop['name']), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                const SizedBox(height: 6),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  StatusPill('${_n(p['stock'])} in stock', color: p['lowStock'] == true ? MMColors.clay : MMColors.moss),
                                  if (p['isActive'] == false) StatusPill('Hidden', color: Colors.grey),
                                ]),
                              ]),
                            ),
                            Text(rupees(_n(p['price'])), style: serif(17)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ])),
    );
  }
}

// =====================================================================================================
// Badges
// =====================================================================================================
class AdminBadgesTab extends ConsumerWidget {
  const AdminBadgesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminMapProvider('/admin/badges'));
    return Container(
      color: kAdminBg,
      child: data.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: apiError(e), onRetry: () => ref.invalidate(adminMapProvider)),
        data: (d) {
          final total = _n(d['totalOwners']);
          final tiers = _list(d['tiers']);
          final achievements = _list(d['achievements']);
          final leaders = _list(d['leaders']);
          double share(num a) => total <= 0 ? 0.0 : (a / total).toDouble();
          return _page(ListView(padding: const EdgeInsets.all(16), children: [
            Reveal(
              index: 0,
              child: HeroCard(
                title: 'Entrepreneur badges',
                child: Row(children: [
                  CountUp(value: total, format: (v) => '${v.round()}', style: serif(40, color: Colors.white)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('shop owners. Badges grow with orders their shops have delivered, plus ratings and an approved shop video.',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            Text('Where owners are today', style: serif(18)),
            const SizedBox(height: 10),
            for (var i = 0; i < tiers.length; i++)
              Reveal(
                index: i + 1,
                child: AdminCard(
                  child: Row(children: [
                    Text(_s(tiers[i]['icon']), style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(_s(tiers[i]['label']), style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text('${_n(tiers[i]['owners'])}', style: serif(18)),
                        ]),
                        Text(_n(tiers[i]['min']) == 0 ? 'Just joined' : 'From ${_n(tiers[i]['min'])} delivered orders',
                            style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: share(_n(tiers[i]['owners']))),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(value: v, minHeight: 9, backgroundColor: MMColors.sage.withOpacity(0.5), color: MMColors.moss),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Text('Achievements', style: serif(18)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final a in achievements) ...[
                Expanded(
                  child: AdminCard(
                    child: Column(children: [
                      Ring(
                        fraction: share(_n(a['owners'])),
                        color: MMColors.marigold,
                        center: Text(_s(a['icon']), style: const TextStyle(fontSize: 26)),
                      ),
                      const SizedBox(height: 8),
                      Text(_s(a['label']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${_n(a['owners'])} of $total owners', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ]),
                  ),
                ),
                if (a != achievements.last) const SizedBox(width: 10),
              ],
            ]),
            const SizedBox(height: 8),
            Text('Top entrepreneurs', style: serif(18)),
            const SizedBox(height: 10),
            if (leaders.isEmpty) const Text('No delivered orders yet.', style: TextStyle(color: Colors.black54)),
            for (var i = 0; i < leaders.length; i++)
              Reveal(
                index: i,
                child: AdminCard(
                  onTap: () => showOwnerDetail(context, _s(leaders[i]['id'])),
                  child: Row(children: [
                    SizedBox(width: 26, child: Text('${i + 1}', style: serif(18))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_s(leaders[i]['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          StatusPill('${_s(_map(leaders[i]['badge'])['icon'])} ${_s(_map(leaders[i]['badge'])['label'])}', color: MMColors.deepOlive),
                          StatusPill('${_n(leaders[i]['delivered'])} delivered', color: MMColors.moss),
                          if (_map(leaders[i]['achievements'])['wellRated'] == true) const StatusPill('⭐ Highly Rated', color: MMColors.marigold),
                          if (_map(leaders[i]['achievements'])['onVideo'] == true) const StatusPill('🎬 On Camera', color: MMColors.clay),
                        ]),
                      ]),
                    ),
                    Text(rupees(_n(leaders[i]['revenue'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]));
        },
      ),
    );
  }
}
