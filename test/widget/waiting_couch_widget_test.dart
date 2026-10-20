import 'package:siz/features/floor_plan/presentation/widgets/waiting_couch_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WaitingCouchWidget displays correct client waiting count', (
    WidgetTester tester,
  ) async {
    bool reserveTapped = false;
    bool queueTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WaitingCouchWidget(
              waitingCount: 3,
              onReserveTap: () => reserveTapped = true,
              onQueueViewTap: () => queueTapped = true,
            ),
          ),
        ),
      ),
    );

    // Verify waiting count label
    expect(find.text('3 clients waiting'), findsOneWidget);
    expect(find.text('RESERVE WAITING SPOT'), findsOneWidget);

    // Tap Reserve button
    await tester.tap(find.text('RESERVE WAITING SPOT'));
    await tester.pump();
    expect(reserveTapped, isTrue);

    // Tap Couch area
    await tester.tap(find.text('3 clients waiting'));
    await tester.pump();
    expect(queueTapped, isTrue);
  });
}
