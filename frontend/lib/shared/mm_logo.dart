import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Maneyindha Marukatte emblem — marigold bloom with a woman artisan
/// at its heart (Bihu red sari with white weave bands).
class MMLogo extends StatelessWidget {
  final double size;
  final bool tile; // draw the olive rounded tile behind the bloom
  const MMLogo({super.key, this.size = 96, this.tile = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MMLogoPainter(tile: tile)),
    );
  }
}

class _MMLogoPainter extends CustomPainter {
  final bool tile;
  _MMLogoPainter({required this.tile});

  static const olive = Color(0xFF5F7036);
  static const deepOlive = Color(0xFF3E4A22);
  static const cream = Color(0xFFF2EDDD);
  static const marigold = Color(0xFFD9922E);
  static const rust = Color(0xFFB4562E);
  static const bihuRed = Color(0xFFC43A2F);
  static const skin = Color(0xFF8C5A3C);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100; // design space: 100x100
    final center = Offset(50 * s, 50 * s);

    if (tile) {
      final rrect = RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(18 * s));
      canvas.drawRRect(rrect, Paint()..color = olive);
    }

    void petals(double radius, double rx, double ry, Color fill,
        double startDeg, Color? stroke) {
      for (int i = 0; i < 5; i++) {
        final angle = (startDeg + i * 72) * math.pi / 180;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        final rect = Rect.fromCenter(
            center: Offset(0, -radius * s),
            width: 2 * rx * s,
            height: 2 * ry * s);
        canvas.drawOval(rect, Paint()..color = fill);
        if (stroke != null) {
          canvas.drawOval(
              rect,
              Paint()
                ..color = stroke
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.8 * s);
        }
        canvas.restore();
      }
    }

    // back cream petals, front marigold petals
    petals(26, 8.5, 15.5, cream, 36, null);
    petals(24, 7.5, 14, marigold, 0, rust);

    // heart of the bloom
    canvas.drawCircle(center, 17 * s, Paint()..color = cream);
    canvas.drawCircle(
        center,
        17 * s,
        Paint()
          ..color = deepOlive
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 * s);

    // woman: bun with marigold pin, head, bindi, sari with weave bands
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(50 * s, 37.5 * s),
            width: 10 * s, height: 4.4 * s),
        Paint()..color = deepOlive);
    canvas.drawCircle(Offset(50 * s, 36.6 * s), 1.1 * s, Paint()..color = marigold);
    canvas.drawCircle(Offset(50 * s, 43 * s), 4.6 * s, Paint()..color = skin);
    canvas.drawCircle(Offset(50 * s, 41.6 * s), 0.9 * s, Paint()..color = bihuRed);

    final sari = Path()
      ..moveTo(50 * s, 47.5 * s)
      ..lineTo(42.5 * s, 64 * s)
      ..lineTo(57.5 * s, 64 * s)
      ..close();
    canvas.drawPath(sari, Paint()..color = bihuRed);

    final weave = Paint()
      ..color = cream
      ..strokeWidth = 1.0 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(45.0 * s, 59.2 * s), Offset(55.0 * s, 59.2 * s), weave);
    canvas.drawLine(Offset(46.4 * s, 55.6 * s), Offset(53.6 * s, 55.6 * s), weave);
    canvas.drawLine(Offset(47.6 * s, 52.2 * s), Offset(52.4 * s, 52.2 * s),
        Paint()
          ..color = marigold
          ..strokeWidth = 1.0 * s
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _MMLogoPainter old) => old.tile != tile;
}
