import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_theme.dart';

/// The shop's own video ("how we make it"). Starts muted (browsers only allow silent autoplay),
/// loops, and lets the customer unmute, pause or close it. Shows nothing if the video cannot load.
class PromoVideoCard extends StatefulWidget {
  final Map<String, dynamic> video; // {url, posterUrl, title, caption, duration}
  const PromoVideoCard({super.key, required this.video});

  @override
  State<PromoVideoCard> createState() => _PromoVideoCardState();
}

class _PromoVideoCardState extends State<PromoVideoCard> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _closed = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    final url = widget.video['url']?.toString();
    if (url == null || !url.startsWith('https://')) {
      _failed = true;
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _c = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _toggleSound() {
    setState(() => _muted = !_muted);
    _c?.setVolume(_muted ? 0 : 1);
  }

  void _togglePlay() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _closed) return const SizedBox.shrink();
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final title = widget.video['title']?.toString() ?? '';
    final caption = widget.video['caption']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          color: Colors.black,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: AspectRatio(
                aspectRatio: ready ? c.value.aspectRatio : 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  if (ready)
                    GestureDetector(onTap: _togglePlay, child: VideoPlayer(c))
                  else
                    const Center(child: CircularProgressIndicator(color: Colors.white)),
                  Positioned(
                    top: 8, right: 8,
                    child: _RoundButton(icon: Icons.close, label: 'Close video', onTap: () {
                      _c?.pause();
                      setState(() => _closed = true);
                    }),
                  ),
                  if (ready)
                    Positioned(
                      bottom: 8, right: 8,
                      child: _RoundButton(
                        icon: _muted ? Icons.volume_off : Icons.volume_up,
                        label: _muted ? 'Turn sound on' : 'Mute',
                        onTap: _toggleSound,
                      ),
                    ),
                ]),
              ),
            ),
            if (title.isNotEmpty || caption.isNotEmpty)
              Container(
                color: MMColors.deepOlive,
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (title.isNotEmpty)
                    Text(title, style: serif(16, color: MMColors.cream)),
                  if (caption.isNotEmpty)
                    Text(caption, style: const TextStyle(color: MMColors.cream, fontSize: 13)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
