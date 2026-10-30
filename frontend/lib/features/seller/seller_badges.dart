import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// Badge, progress and achievements for the signed-in entrepreneur (customers do not have badges).
final sellerBadgesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.dio.get('/rewards/seller');
  return Map<String, dynamic>.from(res.data['data'] as Map);
});

String _glyph(Map? m) => (m?['icon']?.toString().isNotEmpty ?? false) ? m!['icon'].toString() : '🌱';

/// Dashboard card: current badge, progress to the next one, and every badge / achievement.
/// Shows nothing while loading or if it cannot be loaded, so it never blocks the dashboard.
class SellerBadgesCard extends ConsumerWidget {
  const SellerBadgesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sellerBadgesProvider);
    return data.maybeWhen(
      data: (r) {
        final badge = (r['badge'] as Map?) ?? const {};
        final next = r['next'] as Map?;
        final badges = ((r['badges'] as List?) ?? const []).cast<Map>();
        final achievements = ((r['achievements'] as List?) ?? const []).cast<Map>();
        final delivered = (((r['stats'] as Map?)?['deliveredOrders']) as num?)?.toInt() ?? 0;
        final cur = badges.where((b) => b['id'] == badge['id']).toList();
        final from = cur.isEmpty ? 0 : (cur.first['min'] as num).toInt();
        final to = delivered + ((next?['ordersToGo'] as num?)?.toInt() ?? 0);
        final progress = next == null || to <= from ? 1.0 : ((delivered - from) / (to - from)).clamp(0.0, 1.0).toDouble();
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: MMColors.cream, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_glyph(badge), style: const TextStyle(fontSize: 38)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your badge', style: Theme.of(context).textTheme.bodySmall),
                  Text(badge['label']?.toString() ?? 'New Entrepreneur', style: serif(20)),
                  if ((badge['blurb']?.toString() ?? '').isNotEmpty)
                    Text(badge['blurb'].toString(), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress, minHeight: 8,
                backgroundColor: MMColors.moss.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation(MMColors.moss),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              next == null
                  ? 'You have reached the top badge. Congratulations!'
                  : '${next['ordersToGo']} more delivered order${next['ordersToGo'] == 1 ? '' : 's'} to become ${next['label']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in badges) _Pill(glyph: _glyph(b), label: b['label']?.toString() ?? '', earned: b['earned'] == true),
              for (final a in achievements)
                _Pill(glyph: _glyph(a), label: a['label']?.toString() ?? '', earned: a['earned'] == true, hint: a['hint']?.toString()),
            ]),
            const SizedBox(height: 8),
            Text('Badges are based on orders your shop has delivered, customer ratings and an approved shop video.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _Pill extends StatelessWidget {
  final String glyph;
  final String label;
  final bool earned;
  final String? hint;
  const _Pill({required this.glyph, required this.label, required this.earned, this.hint});

  @override
  Widget build(BuildContext context) {
    final pill = Opacity(
      opacity: earned ? 1 : 0.4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: earned ? MMColors.sage : Colors.black12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(glyph, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (earned) ...[const SizedBox(width: 4), const Icon(Icons.check_circle, size: 14, color: MMColors.moss)],
        ]),
      ),
    );
    return hint == null ? pill : Tooltip(message: hint!, child: pill);
  }
}
