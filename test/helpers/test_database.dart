import 'dart:io';

import 'package:siz/core/auth/account_auth.dart';
import 'package:siz/core/database/database_service.dart';
import 'package:siz/core/repositories/barber_repository.dart';
import 'package:siz/core/repositories/finance_repository.dart';
import 'package:siz/core/repositories/floor_plan_repository.dart';
import 'package:siz/core/repositories/queue_repository.dart';
import 'package:siz/core/repositories/shop_repository.dart';
import 'package:siz/core/security/password_hasher.dart';
import 'package:siz/core/security/session_storage.dart';
import 'package:siz/features/auth_onboarding/domain/shop_profile.dart';
import 'package:siz/features/barber_app/barber_link.dart';
import 'package:siz/features/barbers/data/barber_invites.dart';
import 'package:siz/features/barbers/domain/barber.dart';
import 'package:siz/features/client_app/client_activity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// All repositories wired to one fresh database: one simulated device.
class TestEnv {
  TestEnv._(this.db, this.session, this._dir)
    : shops = ShopRepository(
        dbService: db,
        passwordHasher: const PasswordHasher(iterations: 1000),
        sessionStorage: session,
      ),
      barbers = BarberRepository(dbService: db),
      floor = FloorPlanRepository(dbService: db),
      finance = FinanceRepository(dbService: db),
      queue = QueueRepository(dbService: db),
      auth = LocalAccountAuth(
        db: db,
        hasher: const PasswordHasher(iterations: 1000),
        session: session,
      ),
      invites = BarberInvites(db),
      activity = ClientActivityRepository(db) {
    links = LocalBarberLinkRepository(db, auth);
  }

  static Future<TestEnv> create() async {
    sqfliteFfiInit();
    // A file per device: sqflite shares one connection between databases
    // opened with the same path, so in-memory databases would be shared.
    final dir = Directory.systemTemp.createTempSync('barber_test_');
    final db = DatabaseService(
      factory: databaseFactoryFfiNoIsolate,
      path: '${dir.path}/test.db',
    );
    return TestEnv._(db, InMemorySessionStorage(), dir);
  }

  final DatabaseService db;
  final InMemorySessionStorage session;
  final ShopRepository shops;
  final BarberRepository barbers;
  final FloorPlanRepository floor;
  final FinanceRepository finance;
  final QueueRepository queue;
  final LocalAccountAuth auth;
  final BarberInvites invites;
  final ClientActivityRepository activity;
  late final LocalBarberLinkRepository links;
  final Directory _dir;

  Future<void> dispose() async {
    await db.close();
    _dir.deleteSync(recursive: true);
  }

  /// Registers an owner and creates a 4-chair shop with one barber at
  /// chair 1 (60% commission) and two services.
  Future<ShopFixture> seedShop() async {
    final owner = await shops.registerOwner(
      email: 'Owner@Example.com',
      password: 'password123',
      fullName: 'Owner',
    );
    final barber = Barber(
      id: 'barber-1',
      shopId: '',
      name: 'Sam',
      phone: '555',
      commissionRate: 0.6,
      assignedChair: 1,
      createdAt: DateTime.now(),
    );
    final shop = await shops.setupShopProfile(
      ownerId: owner.id,
      name: 'Blade',
      address: '1 Main St',
      phone: '555-0000',
      totalChairs: 4,
      initialBarbers: [barber],
      services: const [
        ServiceItem(id: 'x', shopId: '', name: 'Haircut', price: 25),
        ServiceItem(id: 'y', shopId: '', name: 'Beard', price: 15),
      ],
    );
    return ShopFixture(shop, barber.id);
  }
}

class ShopFixture {
  const ShopFixture(this.shop, this.barberId);

  final ShopProfile shop;
  final String barberId;

  String get shopId => shop.id;

  String serviceId(String name) =>
      shop.services.firstWhere((s) => s.name == name).id;
}
