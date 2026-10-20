import 'package:siz/features/auth_onboarding/presentation/auth_providers.dart';
import 'package:siz/features/auth_onboarding/presentation/screens/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(isLoading: false);
  }
}

void main() {
  testWidgets('AuthScreen renders fields and validates empty inputs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(_FakeAuthNotifier.new)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    await tester.pump();

    // Check title and inputs
    expect(find.text('Barber Shop Owner Portal'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2)); // Email and Password
    expect(find.text('Sign In to Shop'), findsOneWidget);

    // Tap submit without filling fields
    await tester.tap(find.text('Sign In to Shop'));
    await tester.pump();

    // Verify validation errors appear
    expect(find.text('Please enter an email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);

    // Registration enforces the minimum password length.
    await tester.tap(find.text('New shop owner? Create an account'));
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(3));
    await tester.enterText(find.byType(TextFormField).at(2), 'short');
    await tester.tap(find.text('Register as Shop Owner'));
    await tester.pump();
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
  });
}
