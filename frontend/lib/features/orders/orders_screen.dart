import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/rating_widgets.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import '../checkout/pay_flow.dart';

// ---------------------------------------------------------------------------------------------
// Helpers shared by the list and the detail page
// ---------------------------------------------------------------------------------------------
bool _isPickup(Map o) => o['isSelfPickup'] == true;

/// Wording for the order's current state. Self-pickup orders never "go out for delivery".
String _statusText(Map o) {
  final s = o['status']?.toString() ?? '';
  if (_isPickup(o)) {
    switch (s) {
      case 'pending': return 'Waiting for the shop to confirm';
      case 'confirmed': return 'Confirmed — the shop will get it ready';
      case 'preparing': return 'Being prepared for pickup';
      case 'ready': return 'Ready for pickup';
      case 'delivered': return 'Collected';
    }
  }
  switch (s) {
    case 'pending': return 'Waiting for the shop to confirm';
    case 'confirmed': return 'Confirmed';
    case 'preparing': return 'Being prepared';
    case 'ready': return 'Packed and ready';
    case 'assigned': return 'Delivery partner assigned';
    case 'picked_up': return 'Picked up';
    case 'out_for_delivery': return 'Out for delivery';
    case 'delivered': return 'Delivered';
    case 'cancelled': return 'Cancelled';
    case 'rejected': return 'Rejected by the shop';
    case 'refunded': return 'Refunded';
    case 'payment_failed': return 'Payment failed';
  }
  return s;
}

List<String> _stepLabels(Map o) =>
    _isPickup(o) ? ['Ordered', 'Confirmed', 'Ready for pickup', 'Collected'] : ['Ordered', 'Confirmed', 'On the way', 'Delivered'];

/// Position on the 4-step tracker; null for cancelled / rejected / failed orders (no tracker).
int? _stepOf(Map o) {
  switch (o['status']?.toString()) {
    case 'pending': return 0;
    case 'confirmed':
    case 'preparing': return 1;
    case 'ready': return _isPickup(o) ? 2 : 1;
    case 'assigned':
    case 'picked_up':
    case 'out_for_delivery': return 2;
    case 'delivered': return 3;
  }
  return null;
}

Color _statusColor(String status) {
  switch (status) {
    case 'delivered': return MMColors.moss;
    case 'cancelled':
    case 'rejected':
    case 'payment_failed': return Colors.red.shade400;
    case 'refunded': return Colors.blueGrey;
    default: return MMColors.clay;
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  return d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

List<Map> _items(Map o) => ((o['items'] as List?) ?? const []).whereType<Map>().toList();

/// First product photo of an order item (the server sends the product's images when it can).
String? _photo(Map item) {
  final p = item['product'];
  if (p is Map) {
    final imgs = p['images'];
    if (imgs is List && imgs.isNotEmpty) return imgs.first.toString();
  }
  return null;
}

String _shopName(Map o) => (o['business'] is Map ? (o['business'] as Map)['name']?.toString() : null) ?? 'the shop';

bool _needsPayment(Map o) {
  final p = o['payment'];
  return p is Map && p['method'] == 'razorpay' && p['status'] != 'paid' && o['status'] == 'pending';
}

bool _canCancel(Map o) => o['status'] == 'pending' || o['status'] == 'confirmed';

class _Thumb extends StatelessWidget {
  final String? url;
  final double size;
  const _Thumb({this.url, this.size = 72});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size, height: size, color: MMColors.sage.withOpacity(0.35),
          child: url != null
              ? Image.network(url!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag_outlined, color: MMColors.moss))
              : const Icon(Icons.shopping_bag_outlined, color: MMColors.moss),
        ),
      );
}

Future<bool> _cancelOrder(BuildContext context, WidgetRef ref, Map o) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancel this order?'),
      content: const Text('The shop will be told. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep order')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Cancel order'))),
      ],
    ),
  );
  if (yes != true) return false;
  try {
    await ApiClient.dio.patch('/orders/${o['_id']}/status', data: {'status': 'cancelled'});
    ref.invalidate(ordersProvider);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order cancelled.')));
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    return false;
  }
}

Future<void> _payNow(BuildContext context, WidgetRef ref, Map o) async {
  final r = await payForOrder(o['_id'].toString());
  ref.invalidate(ordersProvider);
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message)));
}

/// "Rate your order" appears only while this order still has unrated items (from /reviews/to-rate).
class _RateButton extends ConsumerWidget {
  final String orderId;
  const _RateButton({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(toRateProvider).valueOrNull ?? const [];
    final entry = pending.where((e) => e['orderId'].toString() == orderId).toList();
    if (entry.isEmpty) return const SizedBox.shrink();
    final items = ((entry.first['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () async {
        final saved = await showRateOrderSheet(context, orderId: orderId, items: items);
        ref.invalidate(toRateProvider);
        ref.invalidate(shopsProvider);
        if (saved && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for rating!')));
        }
      },
      icon: const Icon(Icons.star_rounded, size: 18),
      label: const Text('Rate your order'),
    );
  }
}

/// Re-reads the orders every few seconds while a page is open, so a status the shop just changed
/// (confirmed, ready, collected...) shows up without the customer having to refresh.
class _AutoRefresh extends ConsumerStatefulWidget {
  final Widget child;
  const _AutoRefresh({required this.child});
  @override
  ConsumerState<_AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends ConsumerState<_AutoRefresh> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    // Fresh data on open, then every 8 seconds.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) ref.invalidate(ordersProvider); });
    _timer = Timer.periodic(const Duration(seconds: 8), (_) { if (mounted) ref.invalidate(ordersProvider); });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------------------------
// Order list ("Your Orders")
// ---------------------------------------------------------------------------------------------
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go('/app');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final appBar = AppBar(
      leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => _back(context)),
      title: Text(context.tr('Your orders')),
    );
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: FilledButton(onPressed: () => context.push('/login'), child: Text(context.tr('Sign in to see your orders'))),
        ),
      );
    }

    final orders = ref.watch(ordersProvider);
    return _AutoRefresh(child: Scaffold(
      appBar: appBar,
      body: orders.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: 'Could not load orders.', onRetry: () => ref.invalidate(ordersProvider)),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(ordersProvider),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: EmptyView(message: context.tr('No orders yet.\nYour orders will show up here.')),
                    )
                  else
                    for (final o in items) _OrderCard(order: o),
                  const SizedBox(height: 8),
                  const _DiscoverMore(),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

class _OrderCard extends ConsumerWidget {
  final Map order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = order;
    final amounts = (o['amounts'] as Map?) ?? const {};
    final status = o['status']?.toString() ?? '';
    final items = _items(o);
    final first = items.isEmpty ? null : items.first;
    final color = _statusColor(status);
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(order: o)));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: MMColors.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MMColors.sage.withOpacity(0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          color: MMColors.sage.withOpacity(0.35),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            _Meta('ORDER PLACED', _date(o['createdAt'])),
            const SizedBox(width: 20),
            _Meta('TOTAL', rupees(amounts['total'])),
            const Spacer(),
            Flexible(child: _Meta('ORDER #', '${o['orderNumber']}', end: true)),
          ]),
        ),
        InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Thumb(url: first == null ? null : _photo(first), size: 76),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr(_statusText(o)), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
                  const SizedBox(height: 4),
                  Text(
                    items.map((it) => '${it['name']} × ${it['quantity']}').join(', '),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(_isPickup(o) ? 'Pick up from ${_shopName(o)}' : 'From ${_shopName(o)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: open, child: Text(_stepOf(o) == null ? 'View order' : 'Track order')),
            if (_needsPayment(o))
              OutlinedButton.icon(
                onPressed: () => _payNow(context, ref, o),
                icon: const Icon(Icons.lock_outline, size: 18),
                label: Text(context.tr('Pay now')),
              ),
            if (_canCancel(o))
              OutlinedButton(onPressed: () => _cancelOrder(context, ref, o), child: Text(context.tr('Cancel order'))),
            if (status == 'delivered') _RateButton(orderId: o['_id'].toString()),
          ]),
        ),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  final bool end;
  const _Meta(this.label, this.value, {this.end = false});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54, letterSpacing: 0.4)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      );
}

/// Keeps the page from ending in empty space: a row of products to browse.
class _DiscoverMore extends ConsumerWidget {
  const _DiscoverMore();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider(null)).valueOrNull ?? const [];
    if (products.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(context.tr('Discover more home-made products'), style: serif(18)),
      ),
      SizedBox(
        height: 170,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: products.length > 10 ? 10 : products.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final p = products[i];
            final imgs = p['images'];
            final url = imgs is List && imgs.isNotEmpty ? imgs.first.toString() : null;
            return GestureDetector(
              onTap: () => context.push('/product/${p['_id']}'),
              child: SizedBox(
                width: 120,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Thumb(url: url, size: 120),
                  const SizedBox(height: 6),
                  Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(rupees(p['price']), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------
// Order detail / tracking
// ---------------------------------------------------------------------------------------------
class OrderDetailScreen extends ConsumerWidget {
  final Map order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the freshest copy of this order if the list has reloaded since we opened it.
    final fresh = ref.watch(ordersProvider).valueOrNull
        ?.where((e) => e['_id'].toString() == order['_id'].toString()).toList();
    final o = (fresh != null && fresh.isNotEmpty) ? fresh.first : order;
    final status = o['status']?.toString() ?? '';
    final items = _items(o);
    final amounts = (o['amounts'] as Map?) ?? const {};
    final step = _stepOf(o);
    final pickup = _isPickup(o);
    final addr = (o['deliveryAddress'] as Map?) ?? const {};
    final auth = ref.watch(authProvider);

    return _AutoRefresh(child: Scaffold(
      appBar: AppBar(title: Text('Order ${o['orderNumber']}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(context.tr(_statusText(o)), style: serif(24, color: _statusColor(status))),
            ),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _Thumb(url: _photo(items[i]), size: 88),
              ),
            ),
            if (step != null) Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: _Stepper(step: step, labels: _stepLabels(o).map((e) => context.tr(e)).toList()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (_canCancel(o))
                  OutlinedButton(
                    onPressed: () async {
                      if (await _cancelOrder(context, ref, o) && context.mounted) Navigator.of(context).pop();
                    },
                    child: Text(context.tr('Cancel order')),
                  ),
                if (_needsPayment(o))
                  FilledButton.icon(
                    onPressed: () => _payNow(context, ref, o),
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: Text(context.tr('Pay now')),
                  ),
                if (status == 'delivered') _RateButton(orderId: o['_id'].toString()),
                OutlinedButton(onPressed: () => context.push('/assistant'), child: Text(context.tr('Need help?'))),
              ]),
            ),
            const _Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pickup ? 'Self pickup' : 'Delivery address', style: serif(20)),
                const SizedBox(height: 10),
                if (pickup) ...[
                  Text('Collect it from ${_shopName(o)}.', style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    status == 'ready' ? 'Your order is ready — please go to the shop to collect it.' : 'We will tell you here when it is ready.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else ...[
                  Text(auth.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if ((addr['line1'] ?? '').toString().isNotEmpty) Text('${addr['line1']}', style: const TextStyle(fontSize: 15)),
                  Text([addr['city'], addr['pincode']].where((e) => (e ?? '').toString().isNotEmpty).join(', '),
                      style: const TextStyle(fontSize: 15)),
                ],
              ]),
            ),
            const _Divider(),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text('Order info', style: serif(20)),
                initiallyExpanded: true,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _Row('Placed on', _date(o['createdAt'])),
                  _Row('Shop', _shopName(o)),
                  for (final it in items)
                    _Row('${it['name']} × ${it['quantity']}', rupees((it['unitPrice'] as num? ?? 0) * (it['quantity'] as num? ?? 1))),
                  if (((amounts['discount'] as num?) ?? 0) > 0) _Row('Discount', '− ${rupees(amounts['discount'])}'),
                  if (!pickup) _Row('Delivery fee', rupees(amounts['deliveryFee'])),
                  _Row('Total', rupees(amounts['total']), bold: true),
                  _Row('Payment', _paymentText(o)),
                ],
              ),
            ),
          ]),
        ),
      ),
    ));
  }

  static String _paymentText(Map o) {
    final p = o['payment'];
    if (p is! Map) return '—';
    if (p['status'] == 'paid') return 'Paid online';
    if (p['method'] == 'cod') return 'Pay at the shop / on delivery';
    return 'Payment pending';
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(height: 8, color: MMColors.sage.withOpacity(0.35));
}

class _Row extends StatelessWidget {
  final String k;
  final String v;
  final bool bold;
  const _Row(this.k, this.v, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
          const SizedBox(width: 12),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        ]),
      );
}

/// Four circles joined by a line; everything up to the current step is filled.
class _Stepper extends StatelessWidget {
  final int step;
  final List<String> labels;
  const _Stepper({required this.step, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: List.generate(labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          final done = (i ~/ 2) < step;
          return Expanded(child: Container(height: 4, color: done ? MMColors.moss : Colors.black12));
        }
        final idx = i ~/ 2;
        final done = idx <= step;
        return Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? MMColors.moss : Colors.white,
            border: Border.all(color: done ? MMColors.moss : Colors.black26, width: 2),
          ),
          child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
        );
      })),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(labels.length, (i) => Expanded(
          child: Text(
            labels[i],
            textAlign: i == 0 ? TextAlign.left : i == labels.length - 1 ? TextAlign.right : TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: i == step ? FontWeight.w800 : FontWeight.w400,
              color: i <= step ? Colors.black87 : Colors.black45,
            ),
          ),
        )),
      ),
    ]);
  }
}
