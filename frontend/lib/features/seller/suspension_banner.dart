import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repositories.dart';

/// Shown on the shop owner's dashboard while an admin has suspended one of their shops.
class SuspensionBanner extends ConsumerWidget {
  const SuspensionBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(myBusinessesProvider).valueOrNull ?? const [];
    final suspended = shops.where((s) => (s['suspension'] as Map?)?['at'] != null && s['isActive'] == false).toList();
    if (suspended.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final s in suspended)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.block, color: Colors.red.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['name']} is suspended',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade900)),
                const SizedBox(height: 4),
                Text('Customers cannot see it right now.\nReason: ${(s['suspension'] as Map)['reason'] ?? 'not given'}',
                    style: TextStyle(color: Colors.red.shade900)),
                const SizedBox(height: 4),
                Text('Contact support if you think this is a mistake.',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade900)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}
