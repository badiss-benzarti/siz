import 'package:siz/core/demo/demo_seeder.dart';
import 'package:siz/core/sync/sync_engine.dart';
import 'package:siz/core/sync/sync_remote.dart';
import 'package:siz/features/auth_onboarding/domain/shop_profile.dart';
import 'package:siz/features/barbers/domain/barber.dart';
import 'package:siz/features/finance/domain/service_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/test_database.dart';

const _ownerId = '00000000-0000-4000-8000-000000000001';
const _barberId = 'b0000000-0000-4000-8000-000000000001';

/// One phone signed in to the cloud owner account.
class Phone {
  Phone._(this.env, this.engine);

  final TestEnv env;
  final SyncEngine engine;

  static Future<Phone> create(FakeServer server) async {
    final env = await TestEnv.create();
    await env.shops.signInCloudOwner(
      id: _ownerId,
      email: 'owner@test.tn',
      fullName: 'Olfa',
    );
    return Phone._(env, SyncEngine(dbService: env.db, remote: server));
  }

  Future<int> outboxSize() async {
    final db = await env.db.database;
    return (await db.query('sync_outbox')).length;
  }
}

Future<ShopProfile> _setUpSalon(Phone phone) =>
    phone.env.shops.setupShopProfile(
      ownerId: _ownerId,
      name: 'Blade & Crown',
      address: 'Centre Ville',
      phone: '71000000',
      totalChairs: 4,
      initialBarbers: [
        Barber(
          id: _barberId,
          shopId: '',
          name: 'Sami',
          phone: '20000001',
          commissionRate: 0.6,
          assignedChair: 1,
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      services: const [
        ServiceItem(id: '', shopId: '', name: 'Haircut', price: 25),
        ServiceItem(id: '', shopId: '', name: 'Beard', price: 15),
      ],
    );

void main() {
  late FakeServer server;
  late Phone a;
  late ShopProfile shop;

  setUp(() async {
    server = FakeServer();
    a = await Phone.create(server);
    shop = await _setUpSalon(a);
  });

  tearDown(() => a.env.dispose());

  /// A second phone that downloaded the salon at sign-in.
  Future<Phone> secondPhone() async {
    final b = await Phone.create(server);
    addTearDown(b.env.dispose);
    await b.env.shops.importSnapshot(
      (await a.env.shops.loadSnapshot(_ownerId))!,
    );
    return b;
  }

  test('changes of a cloud salon are queued in the same transaction', () async {
    // Shop, 4 chairs, 1 barber, 2 services.
    expect(await a.outboxSize(), 8);
  });

  test('the demo salon is never queued', () async {
    final env = await TestEnv.create();
    addTearDown(env.dispose);
    final db = env.db;
    await DemoSeeder(
      dbService: db,
      shops: env.shops,
      floor: env.floor,
      queue: env.queue,
    ).ensureDemoAccount();
    final rows = await (await db.database).query('sync_outbox');
    expect(rows, isEmpty);
  });

  test('push sends everything and empties the queue', () async {
    final report = await a.engine.push(shop.id);
    expect(report.sent, 8);
    expect(await a.outboxSize(), 0);
    expect(server.rows['barbers']![_barberId]!['name'], 'Sami');
    expect(server.rows['chairs']!['1']!['active_barber_id'], _barberId);
  });

  test('a day at the salon on phone A shows up on phone B', () async {
    await a.engine.push(shop.id);
    final b = await secondPhone();

    final haircut = shop.services.firstWhere((s) => s.name == 'Haircut').id;
    await a.env.queue.addToQueue(shopId: shop.id, clientName: 'Walk-in');
    await a.env.floor.seatClient(
      shopId: shop.id,
      chairNumber: 1,
      clientName: 'Chedi',
    );
    await a.env.floor.checkoutService(
      shopId: shop.id,
      chairNumber: 1,
      serviceIds: [haircut],
      paymentMethod: PaymentMethod.cash,
      tip: 2,
    );
    await a.env.floor.seatClient(
      shopId: shop.id,
      chairNumber: 1,
      clientName: 'Aziz',
    );
    expect((await a.engine.push(shop.id)).rejected, 0);

    final changed = await b.engine.pull(shop.id);
    expect(changed, containsAll(['chairs', 'queue', 'tickets']));

    final tickets = await b.env.finance.getTicketsInRange(
      shopId: shop.id,
      start: DateTime(2000),
      end: DateTime(2100),
    );
    expect(tickets.single.clientName, 'Chedi');
    expect(tickets.single.barberCut, 15);
    expect(tickets.single.tip, 2);
    expect(
      (await b.env.queue.getWaitingQueue(shop.id)).single.clientName,
      'Walk-in',
    );
    final chair = (await b.env.floor.getStations(shop.id)).first;
    expect(chair.activeClientName, 'Aziz');
    expect(chair.activeBarberName, 'Sami');

    // Applying server changes queues nothing to send back.
    expect(await b.outboxSize(), 0);
    // Pulling again changes nothing.
    expect(await b.engine.pull(shop.id), isEmpty);
  });

  test('offline: changes wait, then go out', () async {
    server.offline = true;
    final report = await a.engine.push(shop.id);
    expect(report.offline, isTrue);
    expect(await a.outboxSize(), 8);
    await expectLater(a.engine.pull(shop.id), throwsA(isA<SyncOffline>()));

    server.offline = false;
    expect((await a.engine.push(shop.id)).sent, 8);
  });

  test('an edit made while its row is being sent is not lost', () async {
    server.duringPush = (entity, key) async {
      if (entity == 'barbers') {
        server.duringPush = null;
        await a.env.barbers.updateBarber(
          barberId: _barberId,
          name: 'Sami B.',
          phone: '20000001',
          commissionRate: 0.6,
        );
      }
    };
    await a.engine.push(shop.id);
    expect(await a.outboxSize(), 1);

    await a.engine.push(shop.id);
    expect(server.rows['barbers']![_barberId]!['name'], 'Sami B.');
  });

  test('unsent local edits win over server changes', () async {
    await a.engine.push(shop.id);
    final remoteRow = Map.of(server.rows['barbers']![_barberId]!);
    server.serverWrite('barbers', _barberId, {...remoteRow, 'name': 'Server'});

    await a.env.barbers.updateBarber(
      barberId: _barberId,
      name: 'Local',
      phone: '20000001',
      commissionRate: 0.6,
    );
    await a.engine.pull(shop.id);
    expect((await a.env.barbers.getBarbers(shop.id)).single.name, 'Local');

    await a.engine.push(shop.id);
    expect(server.rows['barbers']![_barberId]!['name'], 'Local');
  });

  test(
    'deleted services and queue entries disappear on other phones',
    () async {
      await a.engine.push(shop.id);
      final b = await secondPhone();
      final item = await a.env.queue.addToQueue(
        shopId: shop.id,
        clientName: 'Walk-in',
      );
      await a.engine.push(shop.id);
      await b.engine.pull(shop.id);
      expect(await b.env.queue.getWaitingQueue(shop.id), hasLength(1));

      final beard = shop.services.firstWhere((s) => s.name == 'Beard').id;
      await a.env.shops.deleteService(shopId: shop.id, serviceId: beard);
      await a.env.queue.removeFromQueue(item.id);
      await a.engine.push(shop.id);

      await b.engine.pull(shop.id);
      expect(await b.env.queue.getWaitingQueue(shop.id), isEmpty);
      expect((await b.env.shops.getServices(shop.id)).map((s) => s.name), [
        'Haircut',
      ]);
    },
  );

  test('a refused change is kept and reported, the rest still goes', () async {
    server.rejectKeys.add(_barberId);
    final report = await a.engine.push(shop.id);
    expect(report.rejected, 1);
    expect(report.sent, 7);

    final backlog = await a.engine.backlog(shop.id);
    expect(backlog.pending, 1);
    expect(backlog.rejected, 1);
    expect(backlog.lastError, 'refused');
  });

  test('a new chair count from another phone resizes the floor', () async {
    await a.engine.push(shop.id);
    final b = await secondPhone();

    await a.env.shops.updateChairCapacity(shopId: shop.id, newCapacity: 6);
    await a.engine.push(shop.id);
    await b.engine.pull(shop.id);
    expect(await b.env.floor.getStations(shop.id), hasLength(6));

    await a.env.shops.updateChairCapacity(shopId: shop.id, newCapacity: 2);
    await a.engine.push(shop.id);
    await b.engine.pull(shop.id);
    expect(await b.env.floor.getStations(shop.id), hasLength(2));
  });

  test('a salon moving to the cloud queues its whole history', () async {
    final env = await TestEnv.create();
    addTearDown(env.dispose);
    final legacy = await env.seedShop();
    final engine = SyncEngine(dbService: env.db, remote: server);
    await env.shops.signInCloudOwner(
      id: _ownerId,
      email: 'owner@example.com',
      fullName: 'Owner',
    );
    await engine.enqueueAll(legacy.shopId);
    expect((await engine.backlog(legacy.shopId)).pending, 8);
  });
}
