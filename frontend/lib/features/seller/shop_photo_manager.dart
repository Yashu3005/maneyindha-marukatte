import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

const _maxPhotoBytes = 3 * 1024 * 1024;

Future<void> showShopPhotoSheet(BuildContext context, Map<String, dynamic> shop) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ShopPhotoSheet(shop: shop),
    ),
  );
}

/// The owner's cover photo: the picture customers see on the home screen, in shop lists and on the shop page.
class _ShopPhotoSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> shop;
  const _ShopPhotoSheet({required this.shop});
  @override
  ConsumerState<_ShopPhotoSheet> createState() => _ShopPhotoSheetState();
}

class _ShopPhotoSheetState extends ConsumerState<_ShopPhotoSheet> {
  late String? _url = shopCover(widget.shop);
  bool _busy = false;
  String? _message;
  bool _isError = false;

  String get _id => widget.shop['_id'].toString();

  void _say(String m, {bool error = false}) => setState(() { _message = m; _isError = error; });

  Future<void> _choose() async {
    setState(() { _busy = true; _message = null; });
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (picked == null) { setState(() => _busy = false); return; } // cancelled
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxPhotoBytes) {
        _say('Please choose an image under 3 MB.', error: true);
        setState(() => _busy = false);
        return;
      }
      final form = FormData.fromMap({'photo': MultipartFile.fromBytes(bytes, filename: picked.name)});
      final res = await ApiClient.dio.post('/businesses/$_id/photo', data: form);
      ref.invalidate(myBusinessesProvider);
      ref.invalidate(shopsProvider);
      if (!mounted) return;
      setState(() { _busy = false; _url = (res.data['data'] as Map)['bannerUrl']?.toString(); });
      _say('Saved. Customers will see this photo.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(apiError(e), error: true);
    }
  }

  Future<void> _remove() async {
    setState(() { _busy = true; _message = null; });
    try {
      await ApiClient.dio.delete('/businesses/$_id/photo');
      ref.invalidate(myBusinessesProvider);
      ref.invalidate(shopsProvider);
      if (!mounted) return;
      setState(() { _busy = false; _url = null; });
      _say('Photo removed.');
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
        Text('Your shop photo', style: serif(22)),
        const SizedBox(height: 6),
        Text('This is the picture customers see for your shop on the home screen and in shop lists. JPEG, PNG or WebP · up to 3 MB.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(height: 170, child: NetImage(_url)),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_message!, style: TextStyle(color: _isError ? MMColors.clay : MMColors.moss)),
          ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _choose,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.photo_library_outlined),
          label: Text(_url == null ? 'Choose from gallery' : 'Replace photo'),
        ),
        if (_url != null) TextButton(onPressed: _busy ? null : _remove, child: const Text('Remove photo')),
      ]),
    );
  }
}

/// Dashboard reminder shown only while the owner's first shop has no photo.
class ShopPhotoNudge extends ConsumerWidget {
  const ShopPhotoNudge({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(myBusinessesProvider).valueOrNull;
    if (shops == null || shops.isEmpty || shopCover(shops.first) != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: MMColors.cream,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => showShopPhotoSheet(context, shops.first),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.add_a_photo_outlined, color: MMColors.moss),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Add a photo of your shop so customers can see it on the home screen.',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      ),
    );
  }
}
