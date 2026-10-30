import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// Up to 3 featured shop videos: the best-rated shops with an approved video (chosen by the server from real ratings).
/// Fetched once per visit / pull-to-refresh, not on every slide.
final promoAdsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.dio.get('/businesses/promo-ads', queryParameters: {'limit': 3});
  final list = (res.data['data'] as List?) ?? const [];
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// False while the customer is on another tab of the app (the home tab stays alive underneath), so the video pauses.
final homeActiveProvider = StateProvider<bool>((ref) => true);

/// The featured-video banner on the home screen. The current video plays right here (muted, as browsers require),
/// and when it finishes the banner slides to the next one; after the last it goes back to the first.
/// Only ONE video player exists at a time. Nothing shows when there are no approved videos.
class PromoAdsCarousel extends ConsumerStatefulWidget {
  const PromoAdsCarousel({super.key});
  @override
  ConsumerState<PromoAdsCarousel> createState() => _PromoAdsCarouselState();
}

class _PromoAdsCarouselState extends ConsumerState<PromoAdsCarousel> with WidgetsBindingObserver {
  static const _loop = 1000; // an "endless" page view, so moving on always slides to the right
  PageController? _pc;
  int _count = 0;
  int _page = 0;          // which video (0..count-1) is current
  bool _foreground = true;
  int _failures = 0;      // consecutive videos that could not play
  bool _stalled = false;  // every video failed in a row: stop and offer a retry

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pc?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg != _foreground && mounted) setState(() => _foreground = fg);
  }

  void _setup(int count) {
    if (count == _count) return;
    _pc?.dispose();
    _count = count;
    _page = 0;
    _failures = 0;
    _stalled = false;
    _pc = PageController(initialPage: count * _loop);
  }

  void _step(int by) {
    final c = _pc;
    if (c == null || !c.hasClients || _count < 2) return;
    final dur = const Duration(milliseconds: 500);
    by > 0 ? c.nextPage(duration: dur, curve: Curves.easeInOut) : c.previousPage(duration: dur, curve: Curves.easeInOut);
  }

  void _ended(int index) {
    if (index != _page) return; // a stale callback from a video that is no longer current
    _step(1);
  }

  void _failed(int index) {
    if (index != _page || !mounted) return;
    _failures += 1;
    if (_failures >= _count) {
      setState(() => _stalled = true); // nothing plays: stop instead of looping through errors forever
    } else {
      _step(1);
    }
  }

  void _played(int index) {
    if (index == _page) _failures = 0;
  }

  @override
  Widget build(BuildContext context) {
    final ads = ref.watch(promoAdsProvider);
    final homeActive = ref.watch(homeActiveProvider);
    final routeActive = TickerMode.of(context); // false while another screen is open on top of the home screen
    final active = _foreground && homeActive && routeActive;
    return ads.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        _setup(items.length);
        if (_stalled) {
          return _Frame(
            child: Container(
              color: MMColors.moss,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Shop videos are not available right now.', style: TextStyle(color: Colors.white)),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () { setState(() { _stalled = false; _failures = 0; }); ref.invalidate(promoAdsProvider); },
                  child: const Text('Try again'),
                ),
              ]),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(children: [
            SizedBox(
              height: 210,
              child: Stack(children: [
                PageView.builder(
                  controller: _pc,
                  onPageChanged: (i) => setState(() => _page = i % items.length),
                  itemBuilder: (context, i) {
                    final idx = i % items.length;
                    final ad = items[idx];
                    final isCurrent = idx == _page;
                    return _Frame(
                      child: isCurrent
                          ? _VideoSlide(
                              key: ValueKey('${ad['businessId']}-${(ad['video'] as Map?)?['url']}'),
                              ad: ad, paused: !active, loopSingle: items.length == 1,
                              onEnded: () => _ended(idx), onFailed: () => _failed(idx), onPlaying: () => _played(idx))
                          : _SlideFace(ad: ad),
                    );
                  },
                ),
                if (items.length > 1) ...[
                  Positioned(left: 10, top: 0, bottom: 0, child: Center(child: _NavButton(icon: Icons.chevron_left, label: 'Previous video', onTap: () => _step(-1)))),
                  Positioned(right: 10, top: 0, bottom: 0, child: Center(child: _NavButton(icon: Icons.chevron_right, label: 'Next video', onTap: () => _step(1)))),
                ],
              ]),
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

/// Rounded frame that every slide sits in.
class _Frame extends StatelessWidget {
  final Widget child;
  const _Frame({required this.child});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox.expand(child: child)),
      );
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: label,
        child: Material(
          color: Colors.black38, shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
              child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, color: Colors.white, size: 22))),
        ),
      );
}

String? _https(dynamic v) {
  final s = v?.toString();
  return (s != null && s.startsWith('https://')) ? s : null;
}

/// Poster, gradient and text: used on its own for slides that are not playing, and as the layer under the video.
class _SlideFace extends StatelessWidget {
  final Map<String, dynamic> ad;
  final Widget? overlay; // play button / sound button etc. from the video slide
  final bool backdrop;   // poster + solid colour behind everything; off while a video is showing underneath
  const _SlideFace({required this.ad, this.overlay, this.backdrop = true});

  @override
  Widget build(BuildContext context) {
    final video = (ad['video'] as Map?) ?? const {};
    final poster = _https(video['posterUrl']) ?? _https(ad['coverUrl']);
    final shop = ad['name']?.toString() ?? '';
    final vt = video['title']?.toString().trim() ?? '';
    final title = vt.isNotEmpty ? vt : shop;
    final caption = video['caption']?.toString().trim() ?? '';
    final rating = ad['rating'] is Map ? ad['rating'] as Map : null;
    return Stack(fit: StackFit.expand, children: [
      if (backdrop) Container(color: MMColors.moss),
      if (backdrop && poster != null)
        Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
      // darkens the bottom so the text stays readable; taps pass through to the video
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0x11000000), Color(0xD9000000)],
            ),
          ),
        ),
      ),
      Positioned(
        left: 14, top: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Featured', style: TextStyle(color: Colors.white, fontSize: 11)),
            if (rating != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
              Text(' ${rating['avg']} (${rating['count']})', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ]),
        ),
      ),
      Positioned(
        left: 16, right: 100, bottom: 12,
        child: IgnorePointer(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(18, color: Colors.white)),
          if (title != shop && shop.isNotEmpty)
            Text(shop, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (caption.isNotEmpty)
            Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ])),
      ),
      Positioned(
        right: 12, bottom: 12,
        child: Semantics(
          button: true, label: 'Visit $shop',
          child: GestureDetector(
            onTap: () => context.push('/business/${ad['businessId']}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Text('Visit shop', style: TextStyle(color: MMColors.deepOlive, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
      if (overlay != null) overlay!,
    ]);
  }
}

/// The current slide: one video player, started automatically (muted), reporting when it ends or fails.
class _VideoSlide extends StatefulWidget {
  final Map<String, dynamic> ad;
  final bool paused;
  final bool loopSingle;
  final VoidCallback onEnded;
  final VoidCallback onFailed;
  final VoidCallback onPlaying;
  const _VideoSlide({
    super.key, required this.ad, required this.paused, required this.loopSingle,
    required this.onEnded, required this.onFailed, required this.onPlaying,
  });
  @override
  State<_VideoSlide> createState() => _VideoSlideState();
}

class _VideoSlideState extends State<_VideoSlide> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _needsTap = false;     // autoplay was blocked: show a play button
  bool _userPaused = false;
  bool _muted = true;
  bool _finished = false;     // makes sure "ended" is reported once
  bool _failedOnce = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = _https((widget.ad['video'] as Map?)?['url']);
    if (url == null) return _fail('bad url');
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _c = c;
    try {
      await c.initialize();
    } catch (_) {
      return _fail('initialize');
    }
    if (!mounted) { await c.dispose(); return; }
    await c.setLooping(widget.loopSingle);
    await c.setVolume(0); // muted: browsers only allow silent autoplay
    c.addListener(_tick);
    setState(() => _ready = true);
    if (!widget.paused) _play();
  }

  void _fail(String why) {
    if (_failedOnce || !mounted) return;
    _failedOnce = true;
    debugPrint('Featured video skipped ($why)'); // never logs the address
    widget.onFailed();
  }

  Future<void> _play() async {
    final c = _c;
    if (c == null || !_ready || _finished) return;
    try {
      await c.play();
    } catch (_) {
      if (mounted) setState(() => _needsTap = true);
      return;
    }
    // If the browser silently refused, offer a play button instead of showing a frozen frame.
    Future.delayed(const Duration(milliseconds: 1200), () {
      final cc = _c;
      if (mounted && cc != null && !widget.paused && !_userPaused && !cc.value.isPlaying && !cc.value.isBuffering && !_finished) {
        setState(() => _needsTap = true);
      }
    });
  }

  void _tick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError) return _fail('playback');
    if (v.isPlaying) {
      widget.onPlaying();
      if (_needsTap) setState(() => _needsTap = false);
    }
    if (_finished || widget.loopSingle) return;
    final d = v.duration;
    // Ended: at (or within a hair of) the end and no longer playing or buffering. Reported once.
    if (d > Duration.zero && v.position >= d - const Duration(milliseconds: 250) && !v.isPlaying && !v.isBuffering) {
      _finished = true;
      widget.onEnded();
    }
  }

  @override
  void didUpdateWidget(covariant _VideoSlide old) {
    super.didUpdateWidget(old);
    final c = _c;
    if (c == null || !_ready || old.paused == widget.paused) return;
    if (widget.paused) {
      c.pause();
    } else if (!_userPaused) {
      _play();
    }
  }

  @override
  void dispose() {
    final c = _c;
    c?.removeListener(_tick);
    c?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null || !_ready) return;
    if (c.value.isPlaying) {
      setState(() => _userPaused = true);
      c.pause();
    } else {
      setState(() { _userPaused = false; _needsTap = false; });
      _play();
    }
  }

  void _toggleSound() {
    setState(() => _muted = !_muted);
    _c?.setVolume(_muted ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = _ready && c != null;
    return Stack(fit: StackFit.expand, children: [
      if (ready)
        GestureDetector(
          onTap: _togglePlay,
          child: FittedBox(
            fit: BoxFit.cover, clipBehavior: Clip.hardEdge,
            child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
          ),
        ),
      // Text, the "Visit shop" button and the controls sit on top of the video; the poster only shows until it starts.
      _SlideFace(
          ad: widget.ad,
          backdrop: !ready,
          overlay: ready
              ? ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: c,
                  builder: (context, v, _) {
                    final showPlay = _needsTap || _userPaused || (!v.isPlaying && !v.isBuffering && widget.paused);
                    return Stack(fit: StackFit.expand, children: [
                      if (v.isBuffering && v.isPlaying == false && !showPlay)
                        const Center(child: CircularProgressIndicator(color: Colors.white)),
                      if (showPlay)
                        Center(
                          child: Semantics(
                            button: true, label: 'Play video',
                            child: GestureDetector(
                              onTap: _togglePlay,
                              child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 60),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 12, top: 10,
                        child: Semantics(
                          button: true, label: _muted ? 'Turn sound on' : 'Mute',
                          child: GestureDetector(
                            onTap: _toggleSound,
                            child: CircleAvatar(
                              radius: 15, backgroundColor: Colors.black54,
                              child: Icon(_muted ? Icons.volume_off : Icons.volume_up, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ]);
                  },
                )
              : const Center(child: CircularProgressIndicator(color: Colors.white)), // while the video starts up
      ),
    ]);
  }
}
