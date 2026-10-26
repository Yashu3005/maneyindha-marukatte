import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small shared UI kit: soft cards, steppers, success dialog. Pure widgets, no network.

List<BoxShadow> softShadow([double opacity = 0.10]) => [
      BoxShadow(
          color: MMColors.deepOlive.withOpacity(opacity),
          blurRadius: 18,
          offset: const Offset(0, 8)),
    ];

class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = MMColors.card,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(0.07),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Icon + title (+ optional subtitle) used to head a section of a form.
class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const SectionHeader({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: MMColors.sage, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 20, color: MMColors.deepOlive),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: serif(18)),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

/// − 2 + control. `onChanged` is not called outside [min, max].
class QuantityStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool enabled;
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool on, VoidCallback tap) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: on ? tap : null,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: on ? MMColors.deepOlive : Colors.black26),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: MMColors.sage.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove, enabled && value > min, () => onChanged(value - 1)),
        SizedBox(
          width: 28,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        btn(Icons.add, enabled && value < max, () => onChanged(value + 1)),
      ]),
    );
  }
}

/// Check mark that pops in. Used on success dialogs.
class AnimatedCheck extends StatelessWidget {
  final double size;
  const AnimatedCheck({super.key, this.size = 84});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (_, t, child) => Transform.scale(scale: t.clamp(0.0, 1.2).toDouble(), child: child),
      child: Container(
        width: size, height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MMColors.heroGradient),
        child: Icon(Icons.check_rounded, color: MMColors.cream, size: size * 0.6),
      ),
    );
  }
}

/// "● ● ○ ○" progress indicator for multi-step flows.
class StepDots extends StatelessWidget {
  final int current; // 1-based
  final int total;
  const StepDots({super.key, required this.current, required this.total});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final on = i < current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == current - 1 ? 26 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: on ? MMColors.cream : MMColors.cream.withOpacity(0.35),
            borderRadius: BorderRadius.circular(6),
          ),
        );
      }),
    );
  }
}

/// A centred celebratory dialog with up to two buttons. Returns when dismissed.
Future<void> showSuccessDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String primaryLabel,
  VoidCallback? onPrimary,
  String? secondaryLabel,
  VoidCallback? onSecondary,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const AnimatedCheck(),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: serif(22)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () { Navigator.pop(ctx); onPrimary?.call(); },
              child: Text(primaryLabel),
            ),
          ),
          if (secondaryLabel != null)
            TextButton(
              onPressed: () { Navigator.pop(ctx); onSecondary?.call(); },
              child: Text(secondaryLabel),
            ),
        ]),
      ),
    ),
  );
}
