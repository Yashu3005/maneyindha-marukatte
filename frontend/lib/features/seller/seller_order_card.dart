import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

/// Invisible helper: re-reads the orders every 8 seconds while the shop's Orders tab is open,
/// so new orders appear without refreshing.
class OrdersAutoRefresh extends ConsumerStatefulWidget {
  const OrdersAutoRefresh({super.key});
  @override
  ConsumerState<OrdersAutoRefresh> createState() => _OrdersAutoRefreshState();
}

class _OrdersAutoRefreshState extends ConsumerState<OrdersAutoRefresh> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) { if (mounted) ref.invalidate(receivedOrdersProvider); });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// One received order, with everything the shop needs: delivery mode, who the customer is, where it goes.
class SellerOrderCard extends StatelessWidget {
  final Map order;
  final String? next;                 // next status the shop can move the order to (null = none)
  final void Function(String next) onAdvance;
  const SellerOrderCard({super.key, required this.order, required this.next, required this.onAdvance});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final status = o['status']?.toString() ?? '';
    final pickup = o['isSelfPickup'] == true;
    final amounts = (o['amounts'] as Map?) ?? const {};
    final customer = o['customer'] is Map ? o['customer'] as Map : const {};
    final name = customer['name']?.toString() ?? '';
    final phone = customer['phone']?.toString() ?? '';
    final addr = (o['deliveryAddress'] as Map?) ?? const {};
    final addressText = [addr['line1'], addr['city'], addr['pincode']]
        .where((e) => (e ?? '').toString().trim().isNotEmpty).join(', ');
    final items = ((o['items'] as List?) ?? const []).whereType<Map>().toList();
    final notes = (o['notes'] ?? '').toString().trim();
    final statusText = pickup && status == 'ready'
        ? 'ready for pickup'
        : pickup && status == 'delivered' ? 'collected' : status.replaceAll('_', ' ');
    final modeColor = pickup ? MMColors.moss : MMColors.clay;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${o['orderNumber']}', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            ),
            Text(rupees(amounts['total']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: modeColor.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(pickup ? Icons.storefront_outlined : Icons.local_shipping_outlined, size: 15, color: modeColor),
                const SizedBox(width: 5),
                Text(pickup ? 'Self pickup — customer collects' : 'Home delivery',
                    style: TextStyle(color: modeColor, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            Chip(label: Text(statusText), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 8),
          for (final it in items)
            Text('${it['name']} × ${it['quantity']}', style: const TextStyle(fontSize: 14)),
          const Divider(height: 22),
          Row(children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(name.isEmpty ? 'Customer' : name, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          if (phone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.phone_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: SelectableText(phone)),
                IconButton(
                  tooltip: 'Call',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.call, size: 20),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                ),
                IconButton(
                  tooltip: 'Copy number',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: phone));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Number copied')));
                    }
                  },
                ),
              ]),
            ),
          if (!pickup)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(addressText.isEmpty ? 'No address given' : addressText)),
              ]),
            ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.sticky_note_2_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('Note: $notes')),
              ]),
            ),
          if (next != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => onAdvance(next!),
                child: Text(next == 'confirmed'
                    ? 'Confirm order'
                    : (pickup && next == 'delivered') ? 'Mark collected' : next!.replaceAll('_', ' ')),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
