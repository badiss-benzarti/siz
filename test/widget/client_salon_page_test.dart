import 'package:siz/core/theme/app_theme.dart';
import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/client_app/client_directory.dart';
import 'package:siz/features/client_app/client_salon_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_client_directory.dart';

/// Lets tab and route animations finish (the room animates forever, so
/// pumpAndSettle would never return).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a client sees the salon live, its barbers, prices and photos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientDirectoryProvider.overrideWithValue(FakeClientDirectory()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ClientSalonPage(shopId: 's1'),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Live: barbers on the chairs, never clients; the waiting line.
    expect(find.text('Blade & Crown'), findsWidgets);
    expect(find.textContaining('#1 · Sami'), findsOneWidget);
    expect(find.textContaining('#2 · Karim'), findsOneWidget);
    expect(find.text('2 clients waiting'), findsOneWidget);
    expect(find.text('2 waiting · 2 barbers on duty'), findsOneWidget);
    expect(find.text('Join the line'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);

    // Barbers: visit ratings, or "New".
    await tester.tap(find.text('Barbers'));
    await settle(tester);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text(' (12)'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);

    // Prices.
    await tester.tap(find.text('Prices'));
    await settle(tester);
    expect(find.text('Haircut'), findsOneWidget);
    expect(find.text(formatMoney(25)), findsOneWidget);

    // Photos, then a post with its comments.
    await tester.tap(find.text('Photos'));
    await settle(tester);
    await tester.tap(find.text('4.5'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Mid skin fade'), findsOneWidget);
    expect(find.text('Clean work'), findsOneWidget);
  });
}
