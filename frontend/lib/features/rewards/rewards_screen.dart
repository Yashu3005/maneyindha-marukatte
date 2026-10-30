import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repositories.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

/// Badge glyph as sent by the server (an emoji), with a safe fallback.
String badgeGlyph(Map? badge) => (badge?['icon']?.toString().isNotEmpty ?? false) ? badge!['icon'].toString() : '🌱';

/// Small pill for headers: "<icon> Regular".
class BadgeChip extends StatelessWidget {
  final Map badge;
  final bool onDark;
  const BadgeChip({super.key, required this.badge, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? MMColors.cream : MMColors.deepOlive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withOpacity(0.16) : MMColors.sage,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(badgeGlyph(badge), style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(badge['label']?.toString() ?? '',
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(rewardsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rewards & coupons')),
      body: data.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: 'Could not load your rewards.',
            onRetry: () => ref.invalidate(rewardsProvider)),
        data: (r) {
          final stats = (r['stats'] as Map?) ?? const {};
          final coupons = ((r['coupons'] as List?) ?? const []).cast<Map>();
          final delivered = (stats['deliveredOrders'] as num?)?.toInt() ?? 0;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  _Stat(label: 'Delivered orders', value: '$delivered'),
                  _Stat(label: 'Last 30 days', value: '${stats['last30Days'] ?? 0}'),
                  _Stat(label: 'Pattern', value: stats['frequency']?.toString() ?? '—'),
                ]),
                const SizedBox(height: 22),
                Text('Your coupons', style: serif(20)),
                const SizedBox(height: 10),
                if (coupons.isEmpty)
                  const EmptyView(message: 'No coupons right now.')
                else
                  for (final c in coupons) _CouponTile(coupon: c),
                const SizedBox(height: 12),
                Text('Coupons unlock as your orders are delivered. Badges are for our entrepreneurs.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: SoftCard(
          child: Column(children: [
            Text(value, style: serif(20), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ]),
        ),
      );
}

String couponValueText(Map c) {
  final v = c['value'];
  if (c['type'] == 'percent') {
    final cap = c['maxDiscount'];
    return '$v% off${cap != null ? ' (up to ${rupees(cap)})' : ''}';
  }
  return '${rupees(v)} off';
}

class _CouponTile extends StatelessWidget {
  final Map coupon;
  const _CouponTile({required this.coupon});

  @override
  Widget build(BuildContext context) {
    final status = coupon['status']?.toString() ?? 'locked';
    final available = status == 'available';
    final code = coupon['code']?.toString() ?? '';
    final min = (coupon['minOrderAmount'] as num?) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: available ? 1 : 0.65,
        child: SoftCard(
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: MMColors.blush, borderRadius: BorderRadius.circular(14)),
              child: Icon(available ? Icons.local_offer : Icons.lock_outline, color: MMColors.clay),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(coupon['title']?.toString() ?? code, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${coupon['description'] ?? couponValueText(coupon)}${min > 0 ? ' · min order ${rupees(min)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (status == 'locked' && (coupon['unlockHint']?.toString() ?? '').isNotEmpty)
                  Text(coupon['unlockHint'].toString(),
                      style: const TextStyle(fontSize: 12, color: MMColors.clay)),
                if (status == 'used')
                  const Text('Already used', style: TextStyle(fontSize: 12)),
              ]),
            ),
            if (available)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Code $code copied. Paste it in your cart.')));
                  }
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(code),
              ),
          ]),
        ),
      ),
    );
  }
}
