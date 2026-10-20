import 'dart:io';

import 'package:siz/core/database/database_service.dart';
import 'package:siz/core/errors/app_exception.dart';
import 'package:siz/core/security/password_hasher.dart';
import 'package:siz/features/finance/domain/service_ticket.dart';
import 'package:siz/features/floor_plan/domain/station.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

Matcher throwsAppException([String? containing]) => throwsA(
  isA<AppException>().having(
    (e) => e.message,
    'message',
    containing == null ? anything : contains(containing),
  ),
);

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  group('Owner accounts', () {
    test('register normalizes email and starts a session', () async {
      final owner = await env.shops.registerOwner(
        email: '  Owner@Example.COM ',
        password: 'password123',
        fullName: 'Owner',
      );
      expect(owner.email, 'owner@example.com');
      expect(owner.passwordHash, startsWith('pbkdf2-sha256\$'));
      expect(await env.session.readActiveOwnerId(), owner.id);
    });

    test('duplicate email, weak password and bad email are rejected', () async {
      await env.shops.registerOwner(
        email: 'a@b.co',
        password: 'password123',
        fullName: 'A',
      );
      expect(
        env.shops.registerOwner(
          email: 'A@B.co',
          password: 'password123',
          fullName: 'A',
        ),
        throwsAppException('already exists'),
      );
      expect(
        env.shops.registerOwner(
          email: 'x@y.co',
          password: 'short',
          fullName: 'X',
        ),
        throwsAppException('at least'),
      );
      expect(
        env.shops.registerOwner(
          email: 'not-an-email',
          password: 'password123',
          fullName: 'X',
        ),
        throwsAppException('valid email'),
      );
    });

    test('login succeeds with the right password only', () async {
      await env.shops.registerOwner(
        email: 'a@b.co',
        password: 'password123',
        fullName: 'A',
      );
      await env.session.clear();

      expect(
        env.shops.loginOwner(email: 'a@b.co', password: 'wrong-pass'),
        throwsAppException('Invalid email or password'),
      );
      final owner = await env.shops.loginOwner(
        email: 'A@B.CO',
        password: 'password123',
      );
      expect(await env.session.readActiveOwnerId(), owner.id);
    });

    test('legacy SHA-256 accounts can log in and are upgraded', () async {
      final db = await env.db.database;
      await db.insert('owners', {
        'id': 'legacy',
        'email': 'old@shop.co',
        'password_hash': PasswordHasher.legacyHash('oldpass', 'abc'),
        'salt': 'abc',
        'full_name': 'Old Owner',
        'created_at': DateTime.now().toIso8601String(),
      });

      final owner = await env.shops.loginOwner(
        email: 'old@shop.co',
        password: 'oldpass',
      );
      expect(owner.passwordHash, startsWith('pbkdf2-sha256\$'));

      final row = (await db.query(
        'owners',
        where: 'id = ?',
        whereArgs: ['legacy'],
      )).single;
      expect(row['password_hash'], owner.passwordHash);
      expect(row['salt'], isNot('abc'));

      await env.shops.loginOwner(email: 'old@shop.co', password: 'oldpass');
    });

    test('a session pointing at a missing owner is cleared', () async {
      await env.session.writeActiveOwnerId('ghost');
      expect(await env.shops.getActiveOwner(), isNull);
      expect(await env.session.readActiveOwnerId(), isNull);
    });
  });

  group('Shop setup', () {
    test(
      'creates chairs, seats the initial barber and stores services',
      () async {
        final f = await env.seedShop();
        final stations = await env.floor.getStations(f.shopId);

        expect(stations, hasLength(4));
        expect(stations.first.status, ChairStatus.available);
        expect(stations.first.activeBarberName, 'Sam');
        expect(f.shop.services.map((s) => s.name), ['Beard', 'Haircut']);
      },
    );

    test('services can be added, edited and deleted but never all', () async {
      final f = await env.seedShop();
      await env.shops.saveService(
        shopId: f.shopId,
        name: 'Shave',
        price: 12.5,
        durationMinutes: 15,
      );
      expect(
        env.shops.saveService(
          shopId: f.shopId,
          name: 'shave',
          price: 1,
          durationMinutes: 5,
        ),
        throwsAppException('already exists'),
      );

      await env.shops.deleteService(
        shopId: f.shopId,
        serviceId: f.serviceId('Beard'),
      );
      await env.shops.deleteService(
        shopId: f.shopId,
        serviceId: f.serviceId('Haircut'),
      );
      final remaining = await env.shops.getServices(f.shopId);
      expect(remaining.single.name, 'Shave');
      expect(
        env.shops.deleteService(
          shopId: f.shopId,
          serviceId: remaining.single.id,
        ),
        throwsAppException('at least one service'),
      );
    });
  });

  group('Floor plan and checkout', () {
    test('full service flow records a correct ticket exactly once', () async {
      final f = await env.seedShop();
      final waiting = await env.queue.addToQueue(
        shopId: f.shopId,
        clientName: 'Jo',
      );

      await env.floor.seatClient(
        shopId: f.shopId,
        chairNumber: 1,
        clientName: waiting.clientName,
        queueItemId: waiting.id,
      );
      expect(await env.queue.getWaitingQueue(f.shopId), isEmpty);

      final ticket = await env.floor.checkoutService(
        shopId: f.shopId,
        chairNumber: 1,
        serviceIds: [f.serviceId('Haircut'), f.serviceId('Beard')],
        paymentMethod: PaymentMethod.card,
        tip: 5,
      );
      expect(ticket.clientName, 'Jo');
      expect(ticket.totalPrice, 40.0);
      expect(ticket.barberCut, 24.0);
      expect(ticket.shopCut, 16.0);
      expect(ticket.tip, 5.0);

      // A second tap on "Complete" must not charge again.
      expect(
        env.floor.checkoutService(
          shopId: f.shopId,
          chairNumber: 1,
          serviceIds: [f.serviceId('Haircut')],
          paymentMethod: PaymentMethod.card,
        ),
        throwsAppException('already been checked out'),
      );

      final stations = await env.floor.getStations(f.shopId);
      expect(stations.first.status, ChairStatus.available);

      final now = DateTime.now();
      final summary = await env.finance.getSummary(
        shopId: f.shopId,
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day + 1),
      );
      expect(summary.totalClientsServed, 1);
      expect(summary.cardTotal, 45.0);
      expect(summary.payoutsByBarber.single.barberName, 'Sam');
      expect(summary.payoutsByBarber.single.totalOwed, 29.0);

      final history = await env.finance.getClientHistory(f.shopId);
      expect(history.single.clientName, 'Jo');
      expect(history.single.totalSpent, 45.0);
    });

    test('checkout uses database prices, not caller-provided ones', () async {
      final f = await env.seedShop();
      await env.floor.seatClient(
        shopId: f.shopId,
        chairNumber: 1,
        clientName: 'Kim',
      );
      expect(
        env.floor.checkoutService(
          shopId: f.shopId,
          chairNumber: 1,
          serviceIds: ['unknown-service'],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsAppException('no longer exists'),
      );
    });

    test('a chair without a barber cannot take a client', () async {
      final f = await env.seedShop();
      expect(
        env.floor.seatClient(shopId: f.shopId, chairNumber: 2, clientName: 'X'),
        throwsAppException('not ready'),
      );
    });

    test('a barber cannot be moved or vacated mid-service', () async {
      final f = await env.seedShop();
      await env.floor.seatClient(
        shopId: f.shopId,
        chairNumber: 1,
        clientName: 'Kim',
      );

      expect(
        env.floor.assignBarberToChair(
          shopId: f.shopId,
          chairNumber: 2,
          barberId: f.barberId,
        ),
        throwsAppException('serving a client'),
      );
      expect(
        env.floor.unassignBarber(shopId: f.shopId, chairNumber: 1),
        throwsAppException('before vacating'),
      );

      await env.floor.cancelService(shopId: f.shopId, chairNumber: 1);
      await env.floor.assignBarberToChair(
        shopId: f.shopId,
        chairNumber: 2,
        barberId: f.barberId,
      );
      final stations = await env.floor.getStations(f.shopId);
      expect(stations[0].status, ChairStatus.empty);
      expect(stations[1].activeBarberId, f.barberId);
      final barber = (await env.barbers.getBarbers(f.shopId)).single;
      expect(barber.assignedChair, 2);
    });

    test('off-duty barbers cannot be assigned and lose their chair', () async {
      final f = await env.seedShop();
      await env.barbers.setOnDuty(f.barberId, false);

      final stations = await env.floor.getStations(f.shopId);
      expect(stations.first.status, ChairStatus.empty);
      expect(
        env.floor.assignBarberToChair(
          shopId: f.shopId,
          chairNumber: 1,
          barberId: f.barberId,
        ),
        throwsAppException('on duty'),
      );
    });
  });

  group('Chair capacity', () {
    test('cannot remove a chair that is serving a client', () async {
      final f = await env.seedShop();
      await env.floor.assignBarberToChair(
        shopId: f.shopId,
        chairNumber: 4,
        barberId: f.barberId,
      );
      await env.floor.seatClient(
        shopId: f.shopId,
        chairNumber: 4,
        clientName: 'Lee',
      );

      expect(
        env.shops.updateChairCapacity(shopId: f.shopId, newCapacity: 3),
        throwsAppException('Chair 4'),
      );
      expect(await env.floor.getStations(f.shopId), hasLength(4));
    });

    test('removing a staffed chair unassigns its barber', () async {
      final f = await env.seedShop();
      await env.floor.assignBarberToChair(
        shopId: f.shopId,
        chairNumber: 4,
        barberId: f.barberId,
      );
      await env.shops.updateChairCapacity(shopId: f.shopId, newCapacity: 3);

      expect(await env.floor.getStations(f.shopId), hasLength(3));
      final barber = (await env.barbers.getBarbers(f.shopId)).single;
      expect(barber.assignedChair, isNull);

      await env.shops.updateChairCapacity(shopId: f.shopId, newCapacity: 6);
      expect(await env.floor.getStations(f.shopId), hasLength(6));
      expect(
        env.shops.updateChairCapacity(shopId: f.shopId, newCapacity: 99),
        throwsAppException('between'),
      );
    });
  });

  group('Barber roster', () {
    test('archiving keeps financial history', () async {
      final f = await env.seedShop();
      await env.floor.seatClient(
        shopId: f.shopId,
        chairNumber: 1,
        clientName: 'Kim',
      );
      expect(
        env.barbers.archiveBarber(f.barberId),
        throwsAppException('serving a client'),
      );

      await env.floor.checkoutService(
        shopId: f.shopId,
        chairNumber: 1,
        serviceIds: [f.serviceId('Haircut')],
        paymentMethod: PaymentMethod.cash,
      );
      await env.barbers.archiveBarber(f.barberId);

      expect(await env.barbers.getBarbers(f.shopId), isEmpty);
      final now = DateTime.now();
      final summary = await env.finance.getSummary(
        shopId: f.shopId,
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day + 1),
      );
      expect(summary.tickets, hasLength(1));
      expect(summary.payoutsByBarber.single.barberName, 'Sam');
    });

    test('commission is validated', () async {
      final f = await env.seedShop();
      expect(
        env.barbers.addBarber(
          shopId: f.shopId,
          name: 'Bad',
          phone: '',
          commissionRate: 1.5,
        ),
        throwsAppException('Commission'),
      );
    });
  });

  group('Schema migrations', () {
    test('a version 1 database upgrades to the current schema', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('barber_db_');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'v1.db');

      final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE barbers (id TEXT PRIMARY KEY, shop_id TEXT NOT NULL, '
              'name TEXT NOT NULL, phone TEXT NOT NULL, commission_rate REAL NOT NULL, '
              'is_on_duty INTEGER NOT NULL DEFAULT 1, assigned_chair INTEGER, '
              'created_at TEXT NOT NULL)',
            );
            for (final t in [
              'tickets',
              'queue',
              'shops',
              'services',
              'chairs',
            ]) {
              await db.execute(
                'CREATE TABLE $t (id TEXT PRIMARY KEY, shop_id TEXT, owner_id TEXT, '
                'timestamp TEXT, status TEXT, created_at TEXT)',
              );
            }
            await db.insert('barbers', {
              'id': 'b',
              'shop_id': 's',
              'name': 'Old',
              'phone': '',
              'commission_rate': 0.5,
              'created_at': DateTime.now().toIso8601String(),
            });
          },
        ),
      );
      await v1.close();

      final service = DatabaseService(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      addTearDown(service.close);
      final db = await service.database;

      expect(await db.getVersion(), DatabaseService.schemaVersion);
      final row = (await db.query('barbers')).single;
      expect(row['is_archived'], 0);
    });
  });
}
