import 'package:siz/core/cloud/cloud_auth.dart';
import 'package:siz/core/cloud/cloud_shop_repository.dart';
import 'package:siz/core/providers/cloud_providers.dart';
import 'package:siz/core/providers/core_providers.dart';
import 'package:siz/core/security/password_hasher.dart';
import 'package:siz/core/sync/sync_controller.dart';
import 'package:siz/core/sync/sync_remote.dart';
import 'package:siz/features/auth_onboarding/domain/shop_profile.dart';
import 'package:siz/features/auth_onboarding/domain/shop_snapshot.dart';
import 'package:siz/features/auth_onboarding/presentation/auth_providers.dart';
import 'package:siz/features/barbers/domain/barber.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud_auth.dart';
import '../helpers/test_database.dart';

/// In-memory stand-in for the salons stored on the server.
class FakeCloudShops implements CloudShopRepository {
  final byOwner = <String, ShopSnapshot>{};
  bool offline = false;
  bool failUploads = false;

  @override
  Future<ShopSnapshot?> fetchOwnedShop(String ownerId) async {
    if (offline) throw offlineError;
    return byOwner[ownerId];
  }

  @override
  Future<void> uploadShop(ShopSnapshot snapshot) async {
    if (offline || failUploads) throw offlineError;
    byOwner[snapshot.shop.ownerId] = snapshot;
  }
}

/// Sync is covered by sync_engine_test; here the server is never reached.
class _Unreachable implements SyncRemote {
  const _Unreachable();

  @override
  Future<void> push(
    String entity,
    String shopId,
    String key,
    Map<String, Object?>? row,
  ) async => throw const SyncOffline();

  @override
  Future<RemoteChanges> pull(
    String entity,
    String shopId,
    DateTime? since,
  ) async => throw const SyncOffline();
}

/// One phone: its own database, sharing the fake server with other phones.
class Device {
  Device._(this.env, this.container);

  static Future<Device> create(FakeCloudAuth auth, FakeCloudShops shops) async {
    final env = await TestEnv.create();
    return Device._(env, _container(env, auth, shops));
  }

  final TestEnv env;
  ProviderContainer container;

  AuthNotifier get auth => container.read(authProvider.notifier);
  AuthState get state => container.read(authProvider);

  /// Simulates closing and reopening the app.
  Future<void> restart(FakeCloudAuth auth, FakeCloudShops shops) async {
    container.dispose();
    container = _container(env, auth, shops);
    await authReady();
  }

  Future<void> authReady() async {
    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    await auth.checkInitialSession();
  }

  Future<void> dispose() async {
    container.dispose();
    await env.dispose();
  }

  static ProviderContainer _container(
    TestEnv env,
    FakeCloudAuth auth,
    FakeCloudShops shops,
  ) => ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWithValue(env.db),
      passwordHasherProvider.overrideWithValue(
        const PasswordHasher(iterations: 1000),
      ),
      sessionStorageProvider.overrideWithValue(env.session),
      cloudAuthProvider.overrideWithValue(auth),
      cloudShopRepositoryProvider.overrideWithValue(shops),
      syncRemoteProvider.overrideWithValue(const _Unreachable()),
    ],
  );
}

Future<bool> _createShop(AuthNotifier auth) => auth.completeOnboarding(
  name: 'Blade & Crown',
  address: 'Centre Ville',
  phone: '71000000',
  totalChairs: 4,
  initialBarbers: [
    Barber(
      id: 'b0000000-0000-4000-8000-000000000001',
      shopId: '',
      name: 'Sami',
      phone: '20000001',
      commissionRate: 0.6,
      assignedChair: 2,
      createdAt: DateTime(2026, 1, 1),
    ),
  ],
  services: const [
    ServiceItem(id: '', shopId: '', name: 'Haircut', price: 25),
    ServiceItem(id: '', shopId: '', name: 'Beard', price: 15),
  ],
);

void main() {
  late FakeCloudAuth cloudAuth;
  late FakeCloudShops cloudShops;
  late Device phone;

  setUp(() async {
    cloudAuth = FakeCloudAuth();
    cloudShops = FakeCloudShops();
    phone = await Device.create(cloudAuth, cloudShops);
    await phone.authReady();
  });

  tearDown(() => phone.dispose());

  test(
    'new owner signs up, creates the salon, and it reaches the server',
    () async {
      expect(
        await phone.auth.register(
          email: ' Owner@Test.tn ',
          password: 'password123',
          fullName: 'Olfa',
        ),
        isTrue,
      );
      expect(phone.state.isAuthenticated, isTrue);
      expect(phone.state.owner!.isCloudAccount, isTrue);
      expect(phone.state.hasCompletedOnboarding, isFalse);

      expect(await _createShop(phone.auth), isTrue);
      final shop = phone.state.shop!;
      final uploaded = cloudShops.byOwner[phone.state.owner!.id]!;
      expect(uploaded.shop.id, shop.id);
      expect(uploaded.shop.services.map((s) => s.id), [
        for (final s in shop.services) s.id,
      ]);
      expect(uploaded.barbers.single.assignedChair, 2);
    },
  );

  test('signing in on a second phone downloads the salon', () async {
    await phone.auth.register(
      email: 'owner@test.tn',
      password: 'password123',
      fullName: 'Olfa',
    );
    await _createShop(phone.auth);
    final original = phone.state.shop!;

    final second = await Device.create(cloudAuth, cloudShops);
    addTearDown(second.dispose);
    await second.authReady();
    expect(
      await second.auth.login(email: 'owner@test.tn', password: 'password123'),
      isTrue,
    );

    final shop = second.state.shop!;
    expect(shop.id, original.id);
    expect(shop.services.length, 2);
    final barbers = await second.env.barbers.getBarbers(shop.id);
    expect(barbers.single.name, 'Sami');
    expect(barbers.single.commissionRate, 0.6);
    final floor = await second.env.floor.getStations(shop.id);
    expect(floor.length, 4);
    expect(
      floor.firstWhere((s) => s.chairNumber == 2).activeBarberName,
      'Sami',
    );
  });

  test('reopening the app works offline', () async {
    await phone.auth.register(
      email: 'owner@test.tn',
      password: 'password123',
      fullName: 'Olfa',
    );
    await _createShop(phone.auth);
    final shopId = phone.state.shop!.id;

    cloudAuth.offline = true;
    cloudShops.offline = true;
    await phone.restart(cloudAuth, cloudShops);
    expect(phone.state.shop?.id, shopId);
    expect(phone.state.errorMessage, isNull);
  });

  test('an ended cloud session asks to sign in again', () async {
    await phone.auth.register(
      email: 'owner@test.tn',
      password: 'password123',
      fullName: 'Olfa',
    );
    cloudAuth.currentUser = null;
    await phone.restart(cloudAuth, cloudShops);
    expect(phone.state.isAuthenticated, isFalse);
  });

  test('a barber account cannot open the owner app', () async {
    await cloudAuth.signUp(
      email: 'sami@test.tn',
      password: 'password123',
      fullName: 'Sami',
      role: AccountRole.barber,
    );
    cloudAuth.currentUser = null;

    expect(
      await phone.auth.login(email: 'sami@test.tn', password: 'password123'),
      isFalse,
    );
    expect(phone.state.isAuthenticated, isFalse);
    expect(phone.state.errorMessage, contains('not a salon owner'));
    expect(cloudAuth.currentUser, isNull);
  });

  test('email confirmation: nobody is signed in until confirmed', () async {
    cloudAuth.requireEmailConfirmation = true;
    expect(
      await phone.auth.register(
        email: 'owner@test.tn',
        password: 'password123',
        fullName: 'Olfa',
      ),
      isTrue,
    );
    expect(phone.state.isAuthenticated, isFalse);
    expect(phone.state.infoMessage, contains('owner@test.tn'));
  });

  test('a failed upload leaves no half-created salon on the phone', () async {
    await phone.auth.register(
      email: 'owner@test.tn',
      password: 'password123',
      fullName: 'Olfa',
    );
    cloudShops.failUploads = true;
    expect(await _createShop(phone.auth), isFalse);
    expect(phone.state.shop, isNull);
    expect(phone.state.errorMessage, isNotNull);
    expect(
      await phone.env.shops.getShopProfileByOwnerId(phone.state.owner!.id),
      isNull,
    );

    cloudShops.failUploads = false;
    expect(await _createShop(phone.auth), isTrue);
  });

  test('the demo works offline and never reaches the cloud', () async {
    cloudAuth.offline = true;
    cloudShops.offline = true;
    expect(await phone.auth.loginDemo(), isTrue);
    expect(phone.state.shop?.name, 'Blade & Crown');
    expect(cloudAuth.calls, 0);
  });

  test('a device-only account still signs in, and moves to the cloud '
      'when registered with the same email', () async {
    final legacy = await phone.env.seedShop();
    await phone.env.shops.logout();

    expect(
      await phone.auth.login(
        email: 'owner@example.com',
        password: 'password123',
      ),
      isTrue,
    );
    expect(phone.state.shop?.id, legacy.shopId);
    expect(phone.state.owner!.isCloudAccount, isFalse);
    await phone.auth.logout();

    expect(
      await phone.auth.register(
        email: 'owner@example.com',
        password: 'password123',
        fullName: 'Owner',
      ),
      isTrue,
    );
    final owner = phone.state.owner!;
    expect(owner.isCloudAccount, isTrue);
    expect(phone.state.shop?.id, legacy.shopId);
    expect(cloudShops.byOwner[owner.id]?.shop.id, legacy.shopId);
    // Its history follows through sync.
    final backlog = await phone.container
        .read(syncEngineProvider)
        .backlog(legacy.shopId);
    expect(backlog.pending, greaterThan(0));
  });
}
