import 'package:siz/core/cloud/cloud_auth.dart';
import 'package:siz/core/errors/app_exception.dart';
import 'package:siz/core/providers/cloud_providers.dart';
import 'package:siz/core/sync/sync_engine.dart';
import 'package:siz/features/barber_app/barber_link.dart';
import 'package:siz/features/barber_app/barber_session.dart';
import 'package:siz/features/barbers/domain/barber.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud_auth.dart';
import '../helpers/fake_sync_server.dart';
import '../helpers/test_database.dart';

/// Stand-in for the server's invitation codes and barber roster.
class FakeBarberLinks implements BarberLinkRepository {
  final codes = <String, BarberLink>{};
  final linked = <String, BarberLink>{};
  String? me;

  @override
  Future<BarberLink?> myLink(String userId) async => linked[userId];

  @override
  Future<InvitePreview?> preview(String code) async {
    final cleaned = SupabaseBarberLinkRepository.normalizeCode(code);
    final link = codes[cleaned];
    return link == null
        ? null
        : InvitePreview(
            code: cleaned,
            shopName: link.shopName,
            barberName: link.barberName,
          );
  }

  @override
  Future<BarberLink> join(String userId, String code) async {
    if (linked.containsKey(userId)) {
      throw const AppException('Your account is already linked to a salon.');
    }
    final link = codes.remove(SupabaseBarberLinkRepository.normalizeCode(code));
    if (link == null) {
      throw const AppException('This code is not valid or has expired.');
    }
    me = userId;
    return linked[userId] = link;
  }

  @override
  Future<void> requestNameChange(String name) async {
    final link = linked[me]!;
    linked[me!] = BarberLink(
      barberId: link.barberId,
      barberName: link.barberName,
      shopId: link.shopId,
      shopName: link.shopName,
      commissionRate: link.commissionRate,
      isOnDuty: link.isOnDuty,
      assignedChair: link.assignedChair,
      requestedName: name.trim(),
    );
  }

  @override
  Future<void> leave() async {
    if (linked.remove(me) == null) {
      throw const AppException('You are not linked to a salon.');
    }
  }
}

const _sami = BarberLink(
  barberId: 'b1',
  barberName: 'Sami',
  shopId: 's1',
  shopName: 'Blade & Crown',
  commissionRate: 0.6,
  isOnDuty: true,
  assignedChair: 1,
);

void main() {
  late FakeCloudAuth auth;
  late FakeBarberLinks links;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        cloudAuthProvider.overrideWithValue(auth),
        barberLinkRepositoryProvider.overrideWithValue(links),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Code, then account: the usual way in for a new barber.
  Future<ProviderContainer> joinedSami() async {
    final c = container();
    final session = c.read(barberSessionProvider.notifier);
    await session.checkCode('ABCD2345');
    await session.registerWithCode(
      email: 'sami@test.tn',
      password: 'password123',
    );
    return c;
  }

  setUp(() {
    auth = FakeCloudAuth();
    links = FakeBarberLinks()..codes['ABCD2345'] = _sami;
  });

  test(
    'the code comes first and shows the salon and the owner\'s name',
    () async {
      final c = container();
      final session = c.read(barberSessionProvider.notifier);

      expect(await session.checkCode('WRONG234'), isFalse);
      expect(c.read(barberSessionProvider).errorMessage, contains('not valid'));
      expect(auth.calls, 0, reason: 'no account is created for a wrong code');

      expect(await session.checkCode(' abcd-2345 '), isTrue);
      final invite = c.read(barberSessionProvider).invite!;
      expect(invite.shopName, 'Blade & Crown');
      expect(invite.barberName, 'Sami');
      expect(c.read(barberSessionProvider).isSignedIn, isFalse);
    },
  );

  test('then the account is created under that name and joins', () async {
    final c = await joinedSami();
    final state = c.read(barberSessionProvider);

    expect(state.user?.role, AccountRole.barber);
    expect(state.user?.fullName, 'Sami');
    expect(state.link?.shopName, 'Blade & Crown');
    expect(state.errorMessage, isNull);
    expect(links.codes, isEmpty, reason: 'the code is used up');
  });

  test('reopening the app finds the salon again', () async {
    await joinedSami();
    final reopened = container();
    expect(reopened.read(barberSessionProvider).isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(reopened.read(barberSessionProvider).link?.barberName, 'Sami');
  });

  test('a name change is only a request until the owner answers', () async {
    final c = await joinedSami();
    await c.read(barberSessionProvider.notifier).requestNameChange(' Samy ');
    final link = c.read(barberSessionProvider).link!;
    expect(link.barberName, 'Sami');
    expect(link.requestedName, 'Samy');
  });

  test('leaving keeps the account but drops the salon', () async {
    final c = await joinedSami();
    await c.read(barberSessionProvider.notifier).leave();
    final state = c.read(barberSessionProvider);
    expect(state.isSignedIn, isTrue);
    expect(state.link, isNull);
    expect(auth.currentUser, isNotNull);

    // A new code from a salon brings them back.
    links.codes['NEWC2345'] = _sami;
    expect(
      await c.read(barberSessionProvider.notifier).join('NEWC2345'),
      isTrue,
    );
  });

  test('an owner account cannot sign in as a barber', () async {
    await auth.signUp(
      email: 'owner@test.tn',
      password: 'password123',
      fullName: 'Olfa',
      role: AccountRole.owner,
    );
    auth.currentUser = null;

    final c = container();
    expect(
      await c
          .read(barberSessionProvider.notifier)
          .login(email: 'owner@test.tn', password: 'password123'),
      isFalse,
    );
    expect(c.read(barberSessionProvider).isSignedIn, isFalse);
    expect(
      c.read(barberSessionProvider).errorMessage,
      contains('not a barber account'),
    );
    expect(auth.currentUser, isNull);
  });

  test('signing out returns to the barber start', () async {
    final c = await joinedSami();
    await c.read(barberSessionProvider.notifier).logout();
    expect(c.read(barberSessionProvider).isSignedIn, isFalse);
    expect(auth.currentUser, isNull);
  });

  test(
    "the owner's phone learns that a barber joined and asks a name",
    () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      const ownerId = '00000000-0000-4000-8000-000000000001';
      await env.shops.signInCloudOwner(
        id: ownerId,
        email: 'owner@test.tn',
        fullName: 'Olfa',
      );
      final barber = Barber(
        id: 'b0000000-0000-4000-8000-000000000001',
        shopId: '',
        name: 'Sami',
        phone: '20000001',
        commissionRate: 0.6,
        createdAt: DateTime(2026),
      );
      final shop = await env.shops.setupShopProfile(
        ownerId: ownerId,
        name: 'Blade',
        address: 'Tunis',
        phone: '71000000',
        totalChairs: 4,
        initialBarbers: [barber],
        services: const [],
      );
      expect(
        (await env.barbers.getBarbers(shop.id)).single.isLinkedToApp,
        false,
      );

      // The salon reached the server; then the server links Sami's account
      // (join_with_invite).
      final server = FakeServer();
      final engine = SyncEngine(dbService: env.db, remote: server);
      await engine.push(shop.id);
      server.serverWrite('barbers', barber.id, {
        ...barber.copyWith(shopId: shop.id).toMap(),
        'profile_id': '00000000-0000-4000-8000-0000000000b1',
        'requested_name': 'Samy',
      });
      await engine.pull(shop.id);

      var sami = (await env.barbers.getBarbers(shop.id)).single;
      expect(sami.isLinkedToApp, true);
      expect(sami.requestedName, 'Samy');

      // The owner accepts: the server renamed him; the phone mirrors it.
      await env.barbers.applyNameAnswer(barber.id, acceptedName: 'Samy');
      sami = (await env.barbers.getBarbers(shop.id)).single;
      expect(sami.name, 'Samy');
      expect(sami.requestedName, isNull);
    },
  );
}
