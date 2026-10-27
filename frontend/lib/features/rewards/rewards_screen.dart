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
      appBar: AppBar(title: const Text('Rewards & badges')),
      body: data.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: 'Could not load your rewards.',
            onRetry: () => ref.invalidate(rewardsProvider)),
        data: (r) {
          final badge = (r['badge'] as Map?) ?? const {};
          final next = r['next'] as Map?;
          final stats = (r['stats'] as Map?) ?? const {};
          final badges = ((r['badges'] as List?) ?? const []).cast<Map>();
          final coupons = ((r['coupons'] as List?) ?? const []).cast<Map>();
          final delivered = (stats['deliveredOrders'] as num?)?.toInt() ?? 0;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: MMColors.heroGradient,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: softShadow(0.2),
                  ),
                  child: Column(children: [
                    Text(badgeGlyph(badge), style: const TextStyle(fontSize: 46)),
                    const SizedBox(height: 8),
                    Text(badge['label']?.toString() ?? 'New', style: serif(26, color: MMColors.cream)),
                    if ((badge['blurb']?.toString() ?? '').isNotEmpty)
                      Text(badge['blurb'].toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MMColors.cream.withOpacity(0.9))),
                    if (next != null) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _progress(delivered, badges, badge, next),
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(MMColors.cream),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${next['ordersToGo'] ?? ''} more delivered order${next['ordersToGo'] == 1 ? '' : 's'} to become ${next['label']}',
                        style: TextStyle(color: MMColors.cream.withOpacity(0.9), fontSize: 12.5),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      Text('You have reached the top badge. Thank you!',
                          style: TextStyle(color: MMColors.cream.withOpacity(0.9))),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 22),
                Text('All badges', style: serif(20)),
                const SizedBox(height: 10),
                for (final b in badges)
                  ListTile(
                    leading: Opacity(
                      opacity: b['earned'] == true ? 1 : 0.35,
                      child: Text(badgeGlyph(b), style: const TextStyle(fontSize: 26)),
                    ),
                    title: Text(b['label']?.toString() ?? ''),
                    subtitle: Text(b['min'] == 0 ? 'Everyone starts here' : '${b['min']} delivered order${b['min'] == 1 ? '' : 's'}'),
                    trailing: b['earned'] == true
                        ? const Icon(Icons.check_circle, color: MMColors.moss)
                        : null,
                  ),
                const SizedBox(height: 12),
                Text('Badges and coupons are based on your delivered orders.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          );
        },
      ),
    );
  }

  static double _progress(int delivered, List<Map> badges, Map badge, Map next) {
    final cur = badges.where((b) => b['id'] == badge['id']).toList();
    final from = cur.isEmpty ? 0 : (cur.first['min'] as num).toInt();
    final to = delivered + ((next['ordersToGo'] as num?)?.toInt() ?? 1);
    if (to <= from) return 1;
    return ((delivered - from) / (to - from)).clamp(0.0, 1.0).toDouble();
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
