import 'package:flutter_test/flutter_test.dart';
import 'package:siz/core/auth/account_auth.dart';
import 'package:siz/core/errors/app_exception.dart';
import 'package:siz/core/security/password_hasher.dart';

import '../helpers/test_database.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  group('accounts on this phone', () {
    test('each role signs up, signs in and is remembered', () async {
      final client = await env.auth.signUp(
        email: ' Lina@Test.TN ',
        password: 'password123',
        fullName: 'Lina',
        role: AccountRole.client,
      );
      expect(client.email, 'lina@test.tn');
      expect(client.role, AccountRole.client);
      expect(env.auth.currentUser?.id, client.id);

      // The password is stored hashed, never in clear.
      final db = await env.db.database;
      final row = (await db.query(
        'owners',
        where: 'id = ?',
        whereArgs: [client.id],
      )).first;
      expect(row['password_hash'], isNot(contains('password123')));
      expect(row['role'], 'client');

      await env.auth.signOut();
      expect(env.auth.currentUser, isNull);
      expect(await env.session.readActiveAccountId(), isNull);

      final again = await env.auth.signIn(
        email: 'lina@test.tn',
        password: 'password123',
      );
      expect(again.id, client.id);

      // A new start of the app restores the account.
      final restarted = LocalAccountAuth(
        db: env.db,
        hasher: const PasswordHasher(iterations: 1000),
        session: env.session,
      );
      await restarted.restore();
      expect(restarted.currentUser?.fullName, 'Lina');
    });

    test('refuses bad input, duplicates and wrong passwords', () async {
      Future<AppUser> signUp(
        String email,
        String password, [
        String name = 'X',
      ]) => env.auth.signUp(
        email: email,
        password: password,
        fullName: name,
        role: AccountRole.barber,
      );

      await expectLater(
        signUp('not-an-email', 'password123'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        signUp('a@b.tn', 'short'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        signUp('a@b.tn', 'password123', ' '),
        throwsA(isA<AppException>()),
      );
      await signUp('a@b.tn', 'password123');
      await expectLater(
        signUp('A@B.tn', 'password123'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        env.auth.signIn(email: 'a@b.tn', password: 'wrong-password'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        env.auth.signIn(email: 'nobody@b.tn', password: 'password123'),
        throwsA(isA<AppException>()),
      );
    });

    test('the owner sign-in only accepts owner accounts', () async {
      await env.auth.signUp(
        email: 'barber@test.tn',
        password: 'password123',
        fullName: 'Sami',
        role: AccountRole.barber,
      );
      await expectLater(
        env.shops.loginOwner(email: 'barber@test.tn', password: 'password123'),
        throwsA(isA<AppException>()),
      );
      final owner = await env.shops.registerOwner(
        email: 'owner@test.tn',
        password: 'password123',
        fullName: 'Owner',
      );
      expect(await env.shops.getOwner(owner.id), isNotNull);
      final barber = await env.auth.signIn(
        email: 'barber@test.tn',
        password: 'password123',
      );
      expect(await env.shops.getOwner(barber.id), isNull);
    });
  });

  group('barbers join with a code from their owner', () {
    test('code first, then the account; name change; leaving', () async {
      final f = await env.seedShop();
      final invite = await env.invites.create(f.barberId);
      expect(invite.code, hasLength(8));

      // The code shows the salon and the name the owner registered.
      final preview = await env.links.preview(
        '${invite.code.substring(0, 4)}-${invite.code.substring(4).toLowerCase()}',
      );
      expect(preview?.shopName, 'Blade');
      expect(preview?.barberName, 'Sam');

      final user = await env.auth.signUp(
        email: 'sam@test.tn',
        password: 'password123',
        fullName: preview!.barberName,
        role: AccountRole.barber,
      );
      final link = await env.links.join(user.id, invite.code);
      expect(link.barberId, f.barberId);
      expect(link.shopName, 'Blade');
      expect(link.commissionRate, 0.6);

      // Single use.
      expect(await env.links.preview(invite.code), isNull);
      await expectLater(
        env.links.join(user.id, invite.code),
        throwsA(isA<AppException>()),
      );

      // A new name waits for the owner.
      await env.links.requestNameChange('Samy');
      expect((await env.links.myLink(user.id))?.requestedName, 'Samy');
      await env.barbers.applyNameAnswer(f.barberId, acceptedName: 'Samy');
      final renamed = await env.links.myLink(user.id);
      expect(renamed?.barberName, 'Samy');
      expect(renamed?.requestedName, isNull);

      // Leaving keeps the account; the salon keeps the roster entry.
      await env.links.leave();
      expect(await env.links.myLink(user.id), isNull);
      final roster = await env.barbers.getBarbers(f.shopId);
      expect(roster.single.name, 'Samy');
      expect(roster.single.profileId, isNull);
      expect(env.auth.currentUser?.id, user.id);
    });

    test('a barber cannot leave in the middle of a cut', () async {
      final f = await env.seedShop();
      final invite = await env.invites.create(f.barberId);
      final user = await env.auth.signUp(
        email: 'sam@test.tn',
        password: 'password123',
        fullName: 'Sam',
        role: AccountRole.barber,
      );
      await env.links.join(user.id, invite.code);
      await env.floor.seatClient(
        shopId: f.shopId,
        chairNumber: 1,
        clientName: 'Omar',
      );
      await expectLater(env.links.leave(), throwsA(isA<AppException>()));
    });

    test('expired or replaced codes do not work', () async {
      final f = await env.seedShop();
      final first = await env.invites.create(f.barberId);
      final second = await env.invites.create(f.barberId);
      expect(await env.links.preview(first.code), isNull);
      expect(await env.links.preview(second.code), isNotNull);

      final db = await env.db.database;
      await db.update('barber_invites', {
        'expires_at': DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      });
      expect(await env.links.preview(second.code), isNull);
      await expectLater(env.links.preview('ABC'), throwsA(isA<AppException>()));
    });
  });
}
