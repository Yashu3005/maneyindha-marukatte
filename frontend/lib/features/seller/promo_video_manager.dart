import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../theme/app_theme.dart';
import '../businesses/promo_video.dart';

/// Lets an approved entrepreneur add, replace or remove the video customers see on her shop page.
Future<void> showPromoVideoSheet(BuildContext context, Map<String, dynamic> shop) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _PromoVideoSheet(shop: shop),
    ),
  );
}

class _PromoVideoSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> shop;
  const _PromoVideoSheet({required this.shop});
  @override
  ConsumerState<_PromoVideoSheet> createState() => _PromoVideoSheetState();
}

class _PromoVideoSheetState extends ConsumerState<_PromoVideoSheet> {
  late Map<String, dynamic>? _video = _initial();
  final _title = TextEditingController();
  final _caption = TextEditingController();
  bool _busy = false;
  double? _progress;
  String? _message;
  bool _isError = false;

  Map<String, dynamic>? _initial() {
    final v = widget.shop['promoVideo'];
    return v is Map && v['url'] != null ? Map<String, dynamic>.from(v) : null;
  }

  String get _shopId => widget.shop['_id'].toString();

  @override
  void initState() {
    super.initState();
    _title.text = _video?['title']?.toString() ?? '';
    _caption.text = _video?['caption']?.toString() ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _caption.dispose();
    super.dispose();
  }

  void _say(String m, {bool error = false}) =>
      setState(() { _message = m; _isError = error; });

  Future<void> _pickAndUpload() async {
    setState(() { _busy = true; _message = null; _progress = null; });
    try {
      // 1. Server signs a one-off upload for this shop (the Cloudinary secret never reaches the browser).
      final sig = (await ApiClient.dio.post('/businesses/$_shopId/promo-video/signature')).data['data'] as Map;
      final limits = (sig['limits'] as Map?) ?? const {};
      final maxBytes = (limits['maxBytes'] as num?)?.toInt() ?? 100 * 1024 * 1024;
      final maxSeconds = (limits['maxSeconds'] as num?)?.toInt() ?? 60;

      final picked = await FilePicker.platform.pickFiles(type: FileType.video, withData: true);
      if (picked == null || picked.files.isEmpty) { setState(() => _busy = false); return; }
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) { _say('Could not read that file. Please try another one.', error: true); setState(() => _busy = false); return; }
      if (bytes.length > maxBytes) {
        _say('That video is ${(bytes.length / 1048576).toStringAsFixed(0)} MB. Please keep it under ${(maxBytes / 1048576).round()} MB (about $maxSeconds seconds).', error: true);
        setState(() => _busy = false);
        return;
      }

      // 2. Straight to Cloudinary. A separate Dio so our login token is never sent to a third party.
      final form = FormData.fromMap({
        for (final e in (sig['fields'] as Map).entries) e.key.toString(): e.value.toString(),
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
      });
      await Dio().post(
        sig['uploadUrl'].toString(),
        data: form,
        onSendProgress: (sent, total) {
          if (total > 0 && mounted) setState(() => _progress = sent / total);
        },
      );

      // 3. Tell our server; it re-checks size, length and format before the video goes live.
      final res = await ApiClient.dio.post('/businesses/$_shopId/promo-video', data: {
        'publicId': sig['publicId'],
        if (_title.text.trim().isNotEmpty) 'title': _title.text.trim(),
        if (_caption.text.trim().isNotEmpty) 'caption': _caption.text.trim(),
      });
      final saved = (res.data['data'] as Map?);
      ref.invalidate(myBusinessesProvider);
      ref.invalidate(shopsProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        final pv = saved?['promoVideo'] ?? saved;
        if (pv is Map && pv['url'] != null) _video = Map<String, dynamic>.from(pv);
      });
      _say('Sent to the admin for approval. It goes live once approved.');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _progress = null; });
      String? hostReason;
      final data = e.response?.data;
      if (data is Map && data['error'] is Map) hostReason = (data['error'] as Map)['message']?.toString();
      _say(e.requestOptions.uri.host.contains('cloudinary')
          ? 'The video host refused the upload${hostReason != null ? ': $hostReason' : '. Please check your connection and try again.'}'
          : apiError(e), error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _progress = null; });
      _say(apiError(e), error: true);
    }
  }

  Future<void> _remove() async {
    setState(() { _busy = true; _message = null; });
    try {
      await ApiClient.dio.delete('/businesses/$_shopId/promo-video');
      ref.invalidate(myBusinessesProvider);
      ref.invalidate(shopsProvider);
      if (!mounted) return;
      setState(() { _busy = false; _video = null; });
      _say('Video removed.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(apiError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Your shop video', style: serif(22)),
        const SizedBox(height: 6),
        Text(
          'Show how you make your products. The admin checks every video first; once approved it plays on your shop page and can appear as an ad on the home screen. '
          'MP4, MOV or WebM · up to 60 seconds · up to 100 MB.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        if (_video != null) _ReviewBanner(video: _video!),
        if (_video != null) PromoVideoCard(key: ValueKey(_video!['url']), video: _video!),
        TextField(
          controller: _title,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Title (optional)', hintText: 'e.g. Hand-made every morning'),
        ),
        TextField(
          controller: _caption,
          maxLength: 240,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Short note (optional)'),
        ),
        if (_progress != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(value: _progress),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(_message!, style: TextStyle(color: _isError ? MMColors.clay : MMColors.moss)),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _pickAndUpload,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.video_library_outlined),
          label: Text(_video == null ? 'Choose a video' : 'Replace video'),
        ),
        if (_video != null)
          TextButton(onPressed: _busy ? null : _remove, child: const Text('Remove video')),
      ]),
    );
  }
}

/// Where the owner's video is in the admin's review.
class _ReviewBanner extends StatelessWidget {
  final Map<String, dynamic> video;
  const _ReviewBanner({required this.video});

  @override
  Widget build(BuildContext context) {
    final review = video['review'] is Map ? video['review'] as Map : const {};
    final status = (video['status'] ?? review['status'] ?? 'pending').toString();
    final reason = (video['reason'] ?? review['reason'] ?? '').toString();
    final text = switch (status) {
      'approved' => 'Approved — your video is live.',
      'rejected' => reason.isEmpty ? 'Rejected by the admin. Please upload a new video.' : 'Rejected: $reason',
      _ => 'Waiting for the admin to approve it. Customers cannot see it yet.',
    };
    final color = status == 'approved' ? MMColors.moss : status == 'rejected' ? MMColors.clay : Colors.orange.shade800;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color)),
      ),
    );
  }
}
