import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/rg_colors.dart';
import '../i18n/strings.dart';

/// Brand mark drawn with a CustomPainter (no image asset): a crimson disc with
/// gold sun-rays. The wordmark is the TENANT's brand name (Strings.brandName,
/// set from /app-config), so it's white-label — never a hardcoded brand.
class RgLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  const RgLogo({super.key, this.size = 120, this.showWordmark = false});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _RgMarkPainter(red: c.redDeep, gold: c.gold, ink: c.ink)),
        ),
        if (showWordmark && Strings.brandName.trim().isNotEmpty) ...[
          SizedBox(height: size * 0.16),
          Builder(builder: (_) {
            final name = Strings.brandName.trim();
            final cut = name.length > 4 ? (name.length / 2).ceil() : name.length;
            return Text.rich(
              TextSpan(children: [
                TextSpan(text: name.substring(0, cut), style: TextStyle(color: c.ink)),
                if (cut < name.length) TextSpan(text: name.substring(cut), style: TextStyle(color: c.red)),
              ]),
              style: TextStyle(
                fontSize: size * 0.22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _RgMarkPainter extends CustomPainter {
  final Color red;
  final Color gold;
  final Color ink;
  _RgMarkPainter({required this.red, required this.gold, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    final ray = Paint()
      ..color = gold
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.018;
    const rays = 16;
    for (var i = 0; i < rays; i++) {
      final a = (i / rays) * 2 * math.pi;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (r * 0.92);
      final p2 = center + Offset(math.cos(a), math.sin(a)) * (r * 1.0);
      canvas.drawLine(p1, p2, ray);
    }

    final disc = Paint()..color = red;
    canvas.drawCircle(center, r * 0.8, disc);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.02
      ..color = gold.withValues(alpha: 0.9);
    canvas.drawCircle(center, r * 0.8, ring);

    final tp = TextPainter(
      text: TextSpan(
        text: 'RG',
        style: TextStyle(
          color: const Color(0xFFFBF6EF),
          fontSize: r * 0.62,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RgMarkPainter old) =>
      old.red != red || old.gold != gold || old.ink != ink;
}
