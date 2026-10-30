import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

// Card look taken from the Best-Flutter-UI-Templates style: soft grey shadow cards, one big-corner gradient hero card
// (fitness template), staggered reveal and count-up numbers, ring and curve charts. Pure widgets, no network.

/// Bumped by the Refresh button; every admin list below re-reads when it changes.
final adminRefreshProvider = StateProvider<int>((_) => 0);

/// A list endpoint (`{ data: [...] }`). The key is the full path with its query string.
final adminListProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, url) async {
  ref.watch(adminRefreshProvider);
  final res = await ApiClient.dio.get(url);
  final d = res.data['data'];
  return d is List ? [for (final e in d) Map<String, dynamic>.from(e as Map)] : <Map<String, dynamic>>[];
});

/// An object endpoint (`{ data: {...} }`).
final adminMapProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, url) async {
  ref.watch(adminRefreshProvider);
  final res = await ApiClient.dio.get(url);
  final d = res.data['data'];
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
});

String adminUrl(String path, Map<String, String?> query) {
  final clean = <String, String>{
    for (final e in query.entries)
      if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
  };
  return Uri(path: path, queryParameters: clean.isEmpty ? null : clean).toString();
}

const kAdminBg = Color(0xFFF4F3EC);

List<BoxShadow> adminShadow([double opacity = 0.2]) =>
    [BoxShadow(color: Colors.grey.withOpacity(opacity), offset: const Offset(1.1, 1.1), blurRadius: 10.0)];

class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const AdminCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: adminShadow()),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Fades and slides a child in; later items take a little longer, so a list rises one after another.
class Reveal extends StatelessWidget {
  final int index;
  final Widget child;
  const Reveal({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final ms = 350 + index.clamp(0, 12).toInt() * 70;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

/// A number that counts up to its value.
class CountUp extends StatelessWidget {
  final num value;
  final String Function(num) format;
  final TextStyle? style;
  const CountUp({super.key, required this.value, required this.format, this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// The big gradient card with one large rounded corner.
class HeroCard extends StatelessWidget {
  final String title;
  final Widget child;
  const HeroCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: MMColors.heroGradient,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8), bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8), topRight: Radius.circular(54),
        ),
        boxShadow: [BoxShadow(color: MMColors.deepOlive.withOpacity(0.35), offset: const Offset(1.1, 4.0), blurRadius: 18.0)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

/// ▲ 12.5% / ▼ 3% against last month, or "new" when there is nothing to compare with.
class DeltaChip extends StatelessWidget {
  final double? pct;
  const DeltaChip(this.pct, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = pct;
    if (p == null) return const Text('new', style: TextStyle(color: Colors.white70, fontSize: 12));
    final up = p >= 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: up ? Colors.lightGreenAccent : Colors.orangeAccent),
      const SizedBox(width: 2),
      Text('${p.abs()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill(this.label, {super.key, this.color = MMColors.moss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// A circular progress ring with a centre label.
class Ring extends StatelessWidget {
  final double fraction;
  final Color color;
  final double size;
  final Widget? center;
  const Ring({super.key, required this.fraction, this.color = MMColors.moss, this.size = 86, this.center});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size, height: size,
        child: CustomPaint(painter: _RingPainter(v, color), child: Center(child: center)),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  _RingPainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (math.min(size.width, size.height) - 12) / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.grey.withOpacity(0.18)..style = PaintingStyle.stroke..strokeWidth = 9);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * fraction, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 9..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.fraction != fraction || o.color != color;
}

/// A smooth curve with a soft gradient under it. Draws itself in when it appears.
class LineChartCard extends StatelessWidget {
  final String title;
  final String? trailing;
  final List<double> values;
  final List<String> labels;
  final Color color;
  const LineChartCard({super.key, required this.title, this.trailing, required this.values, required this.labels, this.color = MMColors.moss});

  @override
  Widget build(BuildContext context) {
    final empty = values.isEmpty || values.every((v) => v == 0);
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          if (trailing != null) Text(trailing!, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 170,
          width: double.infinity,
          child: empty
              ? const Center(child: Text('No activity yet', style: TextStyle(color: Colors.black54)))
              : TweenAnimationBuilder<double>(
                  key: ValueKey('$title|${values.join(',')}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => CustomPaint(painter: _LinePainter(values, labels, color, t)),
                ),
        ),
      ]),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final double progress;
  _LinePainter(this.values, this.labels, this.color, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelH = 20.0;
    const topPad = 16.0;
    final maxV = values.fold<double>(0, math.max);
    if (maxV <= 0) return;
    final w = size.width;
    final h = size.height - labelH - topPad;
    final n = values.length;
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(n == 1 ? w / 2 : i * (w / (n - 1)), topPad + h - (values[i] / maxV) * h * progress),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < n; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final mx = (a.dx + b.dx) / 2;
      line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(pts.last.dx, topPad + h)
      ..lineTo(pts.first.dx, topPad + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.30), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, topPad, w, h)),
    );
    canvas.drawPath(line, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round);
    for (final p in pts) {
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }
    final step = n > 8 ? 2 : 1;
    for (var i = 0; i < n && i < labels.length; i += step) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: const TextStyle(fontSize: 11, color: Colors.black54)),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (pts[i].dx - tp.width / 2).clamp(0.0, math.max(0.0, w - tp.width)).toDouble();
      tp.paint(canvas, Offset(x, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.progress != progress || o.values != values || o.color != color;
}

/// Search box that searches when you press enter or the search icon.
class AdminSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onSearch;
  const AdminSearchField({super.key, required this.hint, required this.onSearch});
  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  final _c = TextEditingController();
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: adminShadow()),
        child: TextField(
          controller: _c,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => widget.onSearch(v.trim()),
          decoration: InputDecoration(
            hintText: widget.hint,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            prefixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => widget.onSearch(_c.text.trim())),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () { _c.clear(); widget.onSearch(''); },
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks the admin to confirm; when [needReason] is true a reason (3+ letters) is required.
/// Returns the reason ('' when none was needed) or null if cancelled.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required bool needReason,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(title: title, message: message, needReason: needReason, confirmLabel: confirmLabel),
  );
}

class _ReasonDialog extends StatefulWidget {
  final String title, message, confirmLabel;
  final bool needReason;
  const _ReasonDialog({required this.title, required this.message, required this.needReason, required this.confirmLabel});
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.message),
        if (widget.needReason) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            maxLength: 300,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Reason (the owner will see this)'),
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (widget.needReason && _c.text.trim().length < 3) ? null : () => Navigator.pop(context, _c.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
