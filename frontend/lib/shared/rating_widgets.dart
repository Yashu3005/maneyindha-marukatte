import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

const _star = Color(0xFFE0A526);

/// Read-only row of stars (supports halves).
class StarRow extends StatelessWidget {
  final double value;
  final double size;
  const StarRow({super.key, required this.value, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          value >= i
              ? Icons.star_rounded
              : (value >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
          size: size,
          color: _star,
        ),
    ]);
  }
}

/// Tap-to-choose 1–5 stars.
class StarPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const StarPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 1; i <= 5; i++)
        IconButton(
          tooltip: '$i star${i == 1 ? '' : 's'}',
          onPressed: () => onChanged(i),
          iconSize: 38,
          icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, color: _star),
        ),
    ]);
  }
}

/// Average + count + 1–5 star spread, from real reviews only.
class RatingSummaryCard extends ConsumerWidget {
  final String businessId;
  const RatingSummaryCard({super.key, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(ratingSummaryProvider(businessId));
    return summary.when(
      loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) {
        final count = (s['count'] as num?)?.toInt() ?? 0;
        if (count == 0) {
          return SoftCard(
            child: Row(children: [
              const Icon(Icons.star_outline_rounded, color: _star),
              const SizedBox(width: 10),
              Expanded(
                child: Text('No ratings yet. Customers can rate after their order is delivered.',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ]),
          );
        }
        final avg = (s['average'] as num?)?.toDouble() ?? 0;
        final dist = (s['distribution'] as Map?) ?? const {};
        int n(int star) => ((dist['$star'] ?? dist[star]) as num?)?.toInt() ?? 0;
        return SoftCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(avg.toStringAsFixed(1), style: serif(40)),
              StarRow(value: avg, size: 18),
              const SizedBox(height: 4),
              Text('$count rating${count == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(width: 20),
            Expanded(
              child: Column(children: [
                for (var star = 5; star >= 1; star--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(width: 14, child: Text('$star', style: const TextStyle(fontSize: 12))),
                      const Icon(Icons.star_rounded, size: 12, color: _star),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: count == 0 ? 0 : n(star) / count,
                            minHeight: 7,
                            backgroundColor: MMColors.sage.withOpacity(0.25),
                            valueColor: const AlwaysStoppedAnimation(_star),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text('${n(star)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Written reviews for a shop.
class ReviewsList extends ConsumerWidget {
  final String businessId;
  const ReviewsList({super.key, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(businessReviewsProvider(businessId));
    return reviews.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        final shown = items.where((r) => (r['comment']?.toString().trim().isNotEmpty ?? false)).take(10).toList();
        if (shown.isEmpty) return const SizedBox.shrink();
        return Column(children: [
          for (final r in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StarRow(value: ((r['rating'] as num?) ?? 0).toDouble(), size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (r['product'] is Map ? (r['product'] as Map)['name'] : null)?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(r['comment'].toString()),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

/// Bottom sheet: pick one delivered item from an order and rate it. Posts the real review; nothing is faked.
Future<bool> showRateOrderSheet(
  BuildContext context, {
  required String orderId,
  required List<Map<String, dynamic>> items, // [{productId, name}]
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _RateSheet(orderId: orderId, items: items),
    ),
  );
  return done == true;
}

class _RateSheet extends StatefulWidget {
  final String orderId;
  final List<Map<String, dynamic>> items;
  const _RateSheet({required this.orderId, required this.items});

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  late String _productId = widget.items.first['productId'].toString();
  int _stars = 0;
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      setState(() => _error = 'Tap a star to choose your rating.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ApiClient.dio.post('/reviews', data: {
        'productId': _productId,
        'orderId': widget.orderId,
        'rating': _stars,
        if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final msg = (e.response?.data is Map ? (e.response!.data as Map)['message'] : null)?.toString();
      if (mounted) setState(() { _busy = false; _error = msg ?? 'Could not save your rating. Please try again.'; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'Could not save your rating. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Rate your order', style: serif(22), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        if (widget.items.length > 1)
          DropdownButtonFormField<String>(
            value: _productId,
            decoration: const InputDecoration(labelText: 'Item'),
            items: [
              for (final it in widget.items)
                DropdownMenuItem(value: it['productId'].toString(), child: Text(it['name'].toString())),
            ],
            onChanged: (v) => setState(() => _productId = v ?? _productId),
          )
        else
          Text(widget.items.first['name'].toString(), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        StarPicker(value: _stars, onChanged: (v) => setState(() => _stars = v)),
        TextField(
          controller: _comment,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Tell others about it (optional)'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: MMColors.clay)),
          ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit rating'),
        ),
      ]),
    );
  }
}
