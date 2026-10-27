import 'package:flutter/material.dart';

/// Maneyindha Marukatte logo. One artwork everywhere: this file (assets/brand/logo.png) is the same picture as the
/// browser tab icon, the opening animation and the logo in the sign-in email.
class MMLogo extends StatelessWidget {
  final double size;
  final bool tile; // kept so older call sites compile; the logo already has its own backdrop
  const MMLogo({super.key, this.size = 96, this.tile = false});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Maneyindha Marukatte',
    );
  }
}

/// The logo fading in and settling, the same intro as the website's opening animation.
class AnimatedBrandLogo extends StatelessWidget {
  final double size;
  final Duration duration;
  const AnimatedBrandLogo({super.key, this.size = 200, this.duration = const Duration(milliseconds: 700)});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0).toDouble(),
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: MMLogo(size: size),
    );
  }
}
