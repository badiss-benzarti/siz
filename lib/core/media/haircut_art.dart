import 'package:flutter/material.dart';

/// The cut drawn by [HaircutArt].
enum HaircutStyle { fade, buzz, pompadour, curly, beard, crop }

/// A drawn portfolio photo: a stylised head showing [style] on a
/// warm gradient. Used for the demo salon's posts, so the app needs no
/// sample photo files.
class HaircutArt extends StatelessWidget {
  const HaircutArt({super.key, required this.style});

  final HaircutStyle style;

  static const _backgrounds = {
    HaircutStyle.fade: [Color(0xFF2B2D42), Color(0xFF5C6784)],
    HaircutStyle.buzz: [Color(0xFF3D2C2E), Color(0xFF8C5E58)],
    HaircutStyle.pompadour: [Color(0xFF1B3A4B), Color(0xFF3E7C8C)],
    HaircutStyle.curly: [Color(0xFF4A3B2A), Color(0xFFB08850)],
    HaircutStyle.beard: [Color(0xFF2F2F2F), Color(0xFF6B6B6B)],
    HaircutStyle.crop: [Color(0xFF3B2F4A), Color(0xFF7A5C99)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _backgrounds[style]!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: CustomPaint(painter: _HeadPainter(style), size: Size.infinite),
    );
  }
}

class _HeadPainter extends CustomPainter {
  const _HeadPainter(this.style);

  final HaircutStyle style;

  static const _skin = Color(0xFFD9A47E);
  static const _hair = Color(0xFF1A1410);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height * 0.56);
    final head = Rect.fromCenter(center: c, width: s * 0.46, height: s * 0.56);
    final skin = Paint()..color = _skin;
    final hair = Paint()..color = _hair;

    // Neck and shoulders.
    canvas
      ..drawRect(
        Rect.fromCenter(
          center: Offset(c.dx, head.bottom),
          width: s * 0.18,
          height: s * 0.2,
        ),
        skin,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset(c.dx, size.height + s * 0.12),
          width: s * 0.9,
          height: s * 0.5,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );

    // Ears and face.
    for (final dx in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx + dx * head.width / 2, c.dy),
          width: s * 0.08,
          height: s * 0.13,
        ),
        skin,
      );
    }
    canvas.drawOval(head, skin);

    // Hair by style.
    final top = head.top;
    switch (style) {
      case HaircutStyle.fade:
      case HaircutStyle.crop:
        canvas.drawPath(
          Path()
            ..moveTo(head.left, c.dy - s * 0.04)
            ..quadraticBezierTo(head.left, top - s * 0.06, c.dx, top - s * 0.07)
            ..quadraticBezierTo(
              head.right,
              top - s * 0.06,
              head.right,
              c.dy - s * 0.04,
            )
            ..lineTo(head.right - s * 0.02, c.dy - s * 0.12)
            ..quadraticBezierTo(
              c.dx,
              top + s * 0.06,
              head.left + s * 0.02,
              c.dy - s * 0.12,
            )
            ..close(),
          hair,
        );
        // Faded sides.
        for (final dx in [-1.0, 1.0]) {
          canvas.drawRect(
            Rect.fromLTWH(
              dx < 0 ? head.left - 1 : head.right - s * 0.05,
              c.dy - s * 0.12,
              s * 0.05,
              s * 0.12,
            ),
            Paint()..color = _hair.withValues(alpha: 0.35),
          );
        }
        if (style == HaircutStyle.crop) {
          canvas.drawRect(
            Rect.fromLTWH(
              head.left + s * 0.06,
              top + s * 0.02,
              head.width - s * 0.12,
              s * 0.05,
            ),
            hair,
          );
        }
      case HaircutStyle.buzz:
        canvas.drawArc(
          head.inflate(1),
          3.3,
          2.8,
          false,
          Paint()
            ..color = _hair.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.05,
        );
      case HaircutStyle.pompadour:
        canvas.drawPath(
          Path()
            ..moveTo(head.left, c.dy - s * 0.06)
            ..quadraticBezierTo(
              head.left - s * 0.02,
              top - s * 0.2,
              c.dx + s * 0.1,
              top - s * 0.17,
            )
            ..quadraticBezierTo(
              head.right + s * 0.06,
              top - s * 0.12,
              head.right,
              c.dy - s * 0.06,
            )
            ..quadraticBezierTo(
              c.dx,
              top + s * 0.05,
              head.left,
              c.dy - s * 0.06,
            )
            ..close(),
          hair,
        );
      case HaircutStyle.curly:
        for (var i = 0; i < 9; i++) {
          final t = i / 8;
          canvas.drawCircle(
            Offset(
              head.left + head.width * t,
              top + s * 0.02 - (0.5 - (t - 0.5).abs()) * s * 0.12,
            ),
            s * 0.07,
            hair,
          );
        }
      case HaircutStyle.beard:
        canvas.drawPath(
          Path()
            ..moveTo(head.left, top + s * 0.1)
            ..quadraticBezierTo(c.dx, top - s * 0.08, head.right, top + s * 0.1)
            ..lineTo(head.right, top + s * 0.14)
            ..quadraticBezierTo(c.dx, top + s * 0.02, head.left, top + s * 0.14)
            ..close(),
          hair,
        );
        canvas.drawPath(
          Path()
            ..moveTo(head.left + s * 0.01, c.dy)
            ..quadraticBezierTo(
              head.left + s * 0.02,
              head.bottom + s * 0.04,
              c.dx,
              head.bottom + s * 0.05,
            )
            ..quadraticBezierTo(
              head.right - s * 0.02,
              head.bottom + s * 0.04,
              head.right - s * 0.01,
              c.dy,
            )
            ..quadraticBezierTo(
              c.dx,
              c.dy + s * 0.14,
              head.left + s * 0.01,
              c.dy,
            )
            ..close(),
          hair,
        );
    }

    // Closed eyes and a calm mouth: a fresh-cut, satisfied client.
    final face = Paint()
      ..color = const Color(0xFF3A2418)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012
      ..strokeCap = StrokeCap.round;
    for (final dx in [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(c.dx + dx * s * 0.08, c.dy + s * 0.01),
          width: s * 0.06,
          height: s * 0.03,
        ),
        0,
        3.14,
        false,
        face,
      );
    }
    if (style != HaircutStyle.beard) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(c.dx, c.dy + s * 0.12),
          width: s * 0.1,
          height: s * 0.05,
        ),
        0.3,
        2.5,
        false,
        face,
      );
    }
  }

  @override
  bool shouldRepaint(_HeadPainter oldDelegate) => oldDelegate.style != style;
}
