import 'package:siz/features/floor_plan/presentation/widgets/room/room_art.dart';
import 'package:flutter/material.dart';

/// The waiting-area card at the front of the room: a couch with one little
/// character per waiting client, and the "reserve a spot" action.
class WaitingCouchWidget extends StatelessWidget {
  const WaitingCouchWidget({
    super.key,
    required this.waitingCount,
    required this.onReserveTap,
    required this.onQueueViewTap,
    this.reserveLabel,
  });

  final int waitingCount;
  final VoidCallback onReserveTap;
  final VoidCallback onQueueViewTap;

  /// Text of the action bar; defaults to "RESERVE WAITING SPOT".
  final String? reserveLabel;

  static const _radius = Radius.circular(22);

  @override
  Widget build(BuildContext context) {
    // The card is clipped to its rounded shape and the outline is drawn on
    // top, so the black action bar reaches the corners with no white edge.
    return Container(
      width: 200,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(_radius),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: const BorderRadius.all(_radius),
        border: Border.all(color: RoomInk.ink, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onQueueViewTap,
            borderRadius: const BorderRadius.vertical(top: _radius),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                children: [
                  CustomPaint(
                    size: const Size(140, 62),
                    painter: _CouchPainter(waiting: waitingCount),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    waitingCount == 1
                        ? '1 client waiting'
                        : '$waitingCount clients waiting',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Material(
            color: RoomInk.ink,
            child: InkWell(
              onTap: onReserveTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
                child: Row(
                  children: [
                    // One line, shrunk if needed: the room relies on the
                    // card's height not changing with long labels.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          reserveLabel ?? 'RESERVE WAITING SPOT',
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.add_circle_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CouchPainter extends CustomPainter {
  const _CouchPainter({required this.waiting});

  final int waiting;

  static const _maxSeated = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final c = canvas;
    final seatWidth = (size.width - 28) / 3;

    c.drawOval(
      Rect.fromLTWH(6, size.height - 8, size.width - 12, 8),
      RoomInk.shadow,
    );

    // Backrest cushions.
    for (var i = 0; i < 3; i++) {
      final left = 14 + i * seatWidth;
      RoomInk.rrect(
        c,
        RRect.fromLTRBR(
          left,
          18,
          left + seatWidth,
          40,
          const Radius.circular(5),
        ),
      );
    }

    // Waiting clients, one per seat.
    final seated = waiting.clamp(0, _maxSeated);
    for (var i = 0; i < seated; i++) {
      final cx = 14 + seatWidth * (i + 0.5);
      RoomInk.shape(
        c,
        Path()
          ..moveTo(cx - 10, 44)
          ..quadraticBezierTo(cx - 10, 26, cx, 26)
          ..quadraticBezierTo(cx + 10, 26, cx + 10, 44)
          ..close(),
      );
      RoomInk.circle(c, Offset(cx, 17), 8.5);
      c
        ..drawCircle(Offset(cx - 3, 16), 1, RoomInk.black)
        ..drawCircle(Offset(cx + 3, 16), 1, RoomInk.black);
    }

    // Seat cushions, arms and legs.
    for (var i = 0; i < 3; i++) {
      final left = 14 + i * seatWidth;
      RoomInk.rrect(
        c,
        RRect.fromLTRBR(
          left,
          40,
          left + seatWidth,
          52,
          const Radius.circular(4),
        ),
      );
    }
    for (final left in [2.0, size.width - 14]) {
      RoomInk.rrect(
        c,
        RRect.fromLTRBR(left, 26, left + 12, 54, const Radius.circular(5)),
      );
    }
    for (final x in [10.0, size.width - 10]) {
      c.drawLine(Offset(x, 54), Offset(x, 58), RoomInk.line);
    }

    if (waiting > _maxSeated) {
      final label = TextPainter(
        text: TextSpan(
          text: '+${waiting - _maxSeated}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final badge = Offset(size.width - 12, 8);
      c.drawCircle(badge, 11, RoomInk.black);
      label.paint(c, badge - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_CouchPainter oldDelegate) =>
      oldDelegate.waiting != waiting;
}
