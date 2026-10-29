import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// Up to 4 random shop videos the admin has approved. A fresh random set on every refresh.
final promoAdsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/businesses/promo-ads', queryParameters: {'limit': 4});
  final list = (res.data['data'] as List?) ?? const [];
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// Home-screen banner that slides to the right every few seconds. Tap an ad to open the shop and watch its video.
/// Shows nothing when there are no approved videos (or they cannot be loaded).
class PromoAdsCarousel extends ConsumerStatefulWidget {
  const PromoAdsCarousel({super.key});
  @override
  ConsumerState<PromoAdsCarousel> createState() => _PromoAdsCarouselState();
}

class _PromoAdsCarouselState extends ConsumerState<PromoAdsCarousel> {
  static const _loop = 1000; // the page view is "endless", so sliding always moves to the right
  PageController? _controller;
  Timer? _timer;
  int _count = 0;
  int _page = 0;

  void _setup(int count) {
    if (count == _count) return;
    _timer?.cancel();
    _controller?.dispose();
    _count = count;
    _page = 0;
    _controller = PageController(initialPage: count * _loop);
    if (count > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        final c = _controller;
        if (!mounted || c == null || !c.hasClients) return;
        c.nextPage(duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ads = ref.watch(promoAdsProvider);
    return ads.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        _setup(items.length);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(children: [
            SizedBox(
              height: 180,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i % items.length),
                itemBuilder: (context, i) => _AdSlide(ad: items[i % items.length]),
              ),
            ),
            if (items.length > 1) ...[
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? MMColors.moss : MMColors.moss.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ]),
            ],
          ]),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _AdSlide extends StatelessWidget {
  final Map<String, dynamic> ad;
  const _AdSlide({required this.ad});

  @override
  Widget build(BuildContext context) {
    final video = (ad['video'] as Map?) ?? const {};
    final poster = video['posterUrl']?.toString();
    final shop = ad['name']?.toString() ?? '';
    final title = (video['title']?.toString().trim().isNotEmpty ?? false) ? video['title'].toString() : shop;
    final caption = video['caption']?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => context.push('/business/${ad['businessId']}'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(fit: StackFit.expand, children: [
            Container(color: MMColors.moss),
            if (poster != null && poster.startsWith('https://'))
              Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x11000000), Color(0xCC000000)],
                ),
              ),
            ),
            Positioned(
              left: 14, top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: const Text('Shop video', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 54)),
            Positioned(
              left: 14, right: 14, bottom: 12,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: serif(18, color: Colors.white)),
                if (title != shop)
                  Text(shop, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (caption != null && caption.isNotEmpty)
                  Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
