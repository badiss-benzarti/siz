import 'package:siz/core/demo/demo_seeder.dart';
import 'package:siz/features/floor_plan/domain/station.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late TestEnv env;
  late DemoSeeder seeder;

  setUp(() async {
    env = await TestEnv.create();
    seeder = DemoSeeder(
      dbService: env.db,
      shops: env.shops,
      floor: env.floor,
      queue: env.queue,
    );
  });
  tearDown(() => env.dispose());

  test('builds a populated demo shop that can be signed into', () async {
    await seeder.ensureDemoAccount();

    final owner = await env.shops.loginOwner(
      email: DemoSeeder.email,
      password: DemoSeeder.password,
    );
    final shop = (await env.shops.getShopProfileByOwnerId(owner.id))!;
    expect(shop.name, 'Blade & Crown');
    expect(shop.services, hasLength(6));

    final barbers = await env.barbers.getBarbers(shop.id);
    expect(barbers, hasLength(5));
    expect(barbers.where((b) => !b.isOnDuty), hasLength(1));

    final stations = await env.floor.getStations(shop.id);
    expect(
      stations.where((s) => s.status == ChairStatus.occupied),
      hasLength(2),
    );
    expect(
      stations.where((s) => s.status == ChairStatus.available),
      hasLength(2),
    );

    expect(await env.queue.getWaitingQueue(shop.id), hasLength(3));

    final now = DateTime.now();
    final month = await env.finance.getSummary(
      shopId: shop.id,
      start: now.subtract(const Duration(days: 31)),
      end: now.add(const Duration(days: 1)),
    );
    expect(month.totalClientsServed, greaterThan(150));
    expect(month.payoutsByBarber, hasLength(4));
    expect(
      month.shopNetRevenue + month.barberPayouts,
      closeTo(month.grossRevenue, 0.01),
    );
    expect(month.tickets.every((t) => t.timestamp.isBefore(now)), isTrue);

    expect(await env.finance.getClientHistory(shop.id), isNotEmpty);
  });

  test('is idempotent', () async {
    await seeder.ensureDemoAccount();
    await seeder.ensureDemoAccount();
    final db = await env.db.database;
    expect(await db.query('owners'), hasLength(1));
    expect(await db.query('shops'), hasLength(1));
  });
}
