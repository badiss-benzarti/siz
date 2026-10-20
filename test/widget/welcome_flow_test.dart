import 'dart:io';

import 'package:siz/app.dart';
import 'package:siz/core/providers/core_providers.dart';
import 'package:siz/features/auth_onboarding/presentation/auth_providers.dart';
import 'package:siz/features/client_app/client_directory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_client_directory.dart';
import '../helpers/fake_account_auth.dart';

class _SignedOut extends AuthNotifier {
  @override
  AuthState build() => const AuthState();
}

void main() {
  // The map caches tiles in the app's cache folder.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });

  testWidgets('the app opens on "Who are you?" and routes each role', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_SignedOut.new),
          accountAuthProvider.overrideWithValue(FakeAccountAuth()),
          clientDirectoryProvider.overrideWithValue(FakeClientDirectory()),
        ],
        child: const SizApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Who are you?'), findsOneWidget);
    // All three spaces are real now.
    expect(find.text('PREVIEW'), findsNothing);

    // Owners go to their sign-in, and can come back.
    await tester.tap(find.text('Salon owner'));
    await tester.pump();
    expect(find.text('Barber Shop Owner Portal'), findsOneWidget);
    expect(find.text('Explore the demo shop'), findsOneWidget);
    await tester.tap(find.text('Who are you?'));
    await tester.pump();

    // Barbers start with their salon code (no owner demo), and can come back.
    await tester.tap(find.text('Barber'));
    await tester.pump();
    expect(find.text('Enter your salon code'), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
    expect(find.text('Explore the demo shop'), findsNothing);
    await tester.tap(find.text('Who are you?'));
    await tester.pump();

    // Clients go straight to the list of salons, no account needed, and
    // can go back from their profile.
    await tester.tap(find.text('Client'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Salons'), findsWidgets);
    expect(find.text('1 salon'), findsOneWidget);
    expect(find.text('Blade & Crown'), findsOneWidget);
    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Create your account'), findsOneWidget);
    await tester.ensureVisible(find.text('Change space'));
    await tester.tap(find.text('Change space'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Salon owner'), findsOneWidget);
  });
}
