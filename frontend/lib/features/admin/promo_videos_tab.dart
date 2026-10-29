import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../businesses/promo_video.dart';

/// Videos shops have uploaded. Nothing reaches customers until the administrator approves it here.
class PromoVideosTab extends StatefulWidget {
  const PromoVideosTab({super.key});
  @override
  State<PromoVideosTab> createState() => _PromoVideosTabState();
}

class _PromoVideosTabState extends State<PromoVideosTab> {
  String _status = 'pending';
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.dio.get('/admin/promo-videos', queryParameters: {'status': _status});
      final list = (res.data['data'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _items = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = apiError(e); _loading = false; });
    }
  }

  Future<void> _review(Map<String, dynamic> item, String action) async {
    String? reason;
    if (action == 'reject') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject this video'),
          content: TextField(
            controller: c, maxLength: 300, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason the shop owner will see'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
          ],
        ),
      );
      if (ok != true) return;
      reason = c.text.trim();
      if (reason.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please give a reason.')));
        return;
      }
    }
    final id = item['businessId'].toString();
    setState(() => _busyId = id);
    try {
      await ApiClient.dio.post('/admin/businesses/$id/promo-video/review',
          data: {'action': action, if (reason != null) 'reason': reason});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(action == 'approve' ? 'Approved — it can now appear on the home screen.' : 'Rejected.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          for (final s in const ['pending', 'approved', 'rejected'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s[0].toUpperCase() + s.substring(1)),
                selected: _status == s,
                onSelected: (_) { _status = s; _load(); },
              ),
            ),
          const Spacer(),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : (_items ?? const []).isEmpty
                    ? Center(child: Text('No $_status videos.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items!.length,
                        itemBuilder: (context, i) {
                          final item = _items![i];
                          final v = Map<String, dynamic>.from(item['promoVideo'] as Map);
                          final busy = _busyId == item['businessId'].toString();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(item['name']?.toString() ?? 'Shop', style: serif(18)),
                                if ((v['title'] ?? '').toString().isNotEmpty) Text(v['title'].toString()),
                                if ((v['caption'] ?? '').toString().isNotEmpty)
                                  Text(v['caption'].toString(), style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 10),
                                PromoVideoCard(key: ValueKey(v['url']), video: v),
                                if (v['status'] == 'rejected' && (v['reason'] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text('Rejected: ${v['reason']}', style: const TextStyle(color: MMColors.clay)),
                                  ),
                                const SizedBox(height: 10),
                                Row(children: [
                                  if (v['status'] != 'approved')
                                    FilledButton(
                                      onPressed: busy ? null : () => _review(item, 'approve'),
                                      child: const Text('Approve'),
                                    ),
                                  const SizedBox(width: 10),
                                  if (v['status'] != 'rejected')
                                    OutlinedButton(
                                      onPressed: busy ? null : () => _review(item, 'reject'),
                                      child: Text(v['status'] == 'approved' ? 'Take down' : 'Reject'),
                                    ),
                                ]),
                              ]),
                            ),
                          );
                        },
                      ),
      ),
    ]);
  }
}
