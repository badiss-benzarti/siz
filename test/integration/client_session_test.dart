import 'package:siz/core/cloud/cloud_auth.dart';
import 'package:siz/core/providers/cloud_providers.dart';
import 'package:siz/features/client_app/client_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud_auth.dart';

void main() {
  late FakeCloudAuth auth;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [cloudAuthProvider.overrideWithValue(auth)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => auth = FakeCloudAuth());

  test('clients browse as guests, then create a client account', () async {
    final c = container();
    expect(c.read(clientSessionProvider).isSignedIn, isFalse);

    expect(
      await c
          .read(clientSessionProvider.notifier)
          .register(
            fullName: ' Chedi ',
            email: 'Chedi@Test.tn',
            password: 'password123',
          ),
      isTrue,
    );
    final user = c.read(clientSessionProvider).user!;
    expect(user.role, AccountRole.client);
    expect(user.fullName, 'Chedi');
    expect(user.email, 'chedi@test.tn');
  });

  test('a name is required', () async {
    final c = container();
    expect(
      await c
          .read(clientSessionProvider.notifier)
          .register(fullName: ' ', email: 'a@b.tn', password: 'password123'),
      isFalse,
    );
    expect(auth.calls, 0);
  });

  test('owner and barber accounts cannot sign in as clients', () async {
    for (final role in [AccountRole.owner, AccountRole.barber]) {
      await auth.signUp(
        email: '${role.name}@test.tn',
        password: 'password123',
        fullName: role.name,
        role: role,
      );
      auth.currentUser = null;
      final c = container();
      expect(
        await c
            .read(clientSessionProvider.notifier)
            .login(email: '${role.name}@test.tn', password: 'password123'),
        isFalse,
      );
      expect(
        c.read(clientSessionProvider).errorMessage,
        contains('not a client account'),
      );
      expect(auth.currentUser, isNull);
    }
  });

  test(
    'reopening the app keeps the client signed in; sign-out works',
    () async {
      await container()
          .read(clientSessionProvider.notifier)
          .register(
            fullName: 'Chedi',
            email: 'c@t.tn',
            password: 'password123',
          );
      final reopened = container();
      expect(reopened.read(clientSessionProvider).isSignedIn, isTrue);
      await reopened.read(clientSessionProvider.notifier).logout();
      expect(reopened.read(clientSessionProvider).isSignedIn, isFalse);
    },
  );
}
