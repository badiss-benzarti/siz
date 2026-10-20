import 'package:siz/core/errors/app_exception.dart';
import 'package:siz/core/sync/sync_engine.dart';
import 'package:siz/features/auth_onboarding/domain/shop_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/test_database.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<ShopProfile> reload(String ownerId) async =>
      (await env.shops.getShopProfileByOwnerId(ownerId))!;

  test('a new salon is open, not placed and hidden from clients', () async {
    final fixture = await env.seedShop();
    final shop = fixture.shop;
    expect(shop.isOpen, isTrue);
    expect(shop.hasLocation, isFalse);
    expect(shop.isListed, isFalse);
  });

  test('clients can only see a salon once it is on the map', () async {
    final fixture = await env.seedShop();
    final id = fixture.shopId;
    final ownerId = fixture.shop.ownerId;

    await expectLater(
      env.shops.setShopListed(shopId: id, isListed: true),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      env.shops.updateShopLocation(shopId: id, latitude: 120, longitude: 10),
      throwsA(isA<AppException>()),
    );

    await env.shops.updateShopLocation(
      shopId: id,
      latitude: 36.8008,
      longitude: 10.18,
    );
    await env.shops.setShopListed(shopId: id, isListed: true);
    await env.shops.setShopOpen(shopId: id, isOpen: false);

    final shop = await reload(ownerId);
    expect(shop.latitude, 36.8008);
    expect(shop.longitude, 10.18);
    expect(shop.isListed, isTrue);
    expect(shop.isOpen, isFalse);
  });

  test('a location chosen during setup is saved with the salon', () async {
    final owner = await env.shops.registerOwner(
      email: 'owner@test.tn',
      password: 'password123',
      fullName: 'Olfa',
    );
    final shop = await env.shops.setupShopProfile(
      ownerId: owner.id,
      name: 'Blade',
      address: 'Tunis',
      phone: '71000000',
      totalChairs: 4,
      initialBarbers: const [],
      services: const [ServiceItem(id: '', shopId: '', name: 'Cut', price: 20)],
      latitude: 36.85,
      longitude: 10.27,
    );
    expect(shop.hasLocation, isTrue);
    expect(shop.isListed, isFalse);
  });

  test('server rows use booleans, device rows use 0/1', () {
    final fromServer = ShopProfile.fromMap({
      'id': 's',
      'owner_id': 'o',
      'name': 'Blade',
      'address': '',
      'phone': '',
      'total_chairs': 4,
      'created_at': '2026-10-08T10:00:00Z',
      'latitude': 36.8,
      'longitude': 10,
      'is_open': false,
      'is_listed': true,
    });
    expect(fromServer.isOpen, isFalse);
    expect(fromServer.isListed, isTrue);
    expect(fromServer.longitude, 10.0);

    final roundTrip = ShopProfile.fromMap(fromServer.toMap());
    expect(roundTrip.isOpen, isFalse);
    expect(roundTrip.isListed, isTrue);
  });

  test('location and switches reach the other phones', () async {
    final server = FakeServer();
    const ownerId = '00000000-0000-4000-8000-000000000001';
    await env.shops.signInCloudOwner(
      id: ownerId,
      email: 'owner@test.tn',
      fullName: 'Olfa',
    );
    final shop = await env.shops.setupShopProfile(
      ownerId: ownerId,
      name: 'Blade',
      address: 'Tunis',
      phone: '71000000',
      totalChairs: 4,
      initialBarbers: const [],
      services: const [ServiceItem(id: '', shopId: '', name: 'Cut', price: 20)],
    );
    final engine = SyncEngine(dbService: env.db, remote: server);
    await engine.push(shop.id);

    final other = await TestEnv.create();
    addTearDown(other.dispose);
    await other.shops.signInCloudOwner(
      id: ownerId,
      email: 'owner@test.tn',
      fullName: 'Olfa',
    );
    await other.shops.importSnapshot((await env.shops.loadSnapshot(ownerId))!);

    await env.shops.updateShopLocation(
      shopId: shop.id,
      latitude: 36.8008,
      longitude: 10.18,
    );
    await env.shops.setShopListed(shopId: shop.id, isListed: true);
    await env.shops.setShopOpen(shopId: shop.id, isOpen: false);
    await engine.push(shop.id);

    await SyncEngine(dbService: other.db, remote: server).pull(shop.id);
    final seen = (await other.shops.getShopProfileByOwnerId(ownerId))!;
    expect(seen.latitude, 36.8008);
    expect(seen.isListed, isTrue);
    expect(seen.isOpen, isFalse);
  });
}
