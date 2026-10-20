import 'package:siz/core/auth/account_auth.dart';
import 'package:siz/core/demo/demo_seeder.dart';
import 'package:siz/core/security/password_hasher.dart';
import 'package:siz/features/barber_app/portfolio.dart';
import 'package:siz/features/client_app/client_directory.dart';
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
      hasher: const PasswordHasher(iterations: 1000),
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

    // Three walk-ins and Adam, from his app.
    expect(await env.queue.getWaitingQueue(shop.id), hasLength(4));

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

  test('every demo account signs in, with its role and its story', () async {
    await seeder.ensureDemoAccount();
    for (final a in DemoSeeder.accounts) {
      final user = await env.auth.signIn(email: a.email, password: a.password);
      expect(user.role.name, a.role, reason: a.email);
    }

    final salons = await LocalClientDirectory(env.db).salons();
    expect(salons.map((s) => s.name), [
      'Blade & Crown',
      'Fade Factory',
      "The Gentlemen's Room",
    ]);
    expect(salons.last.isOpen, isFalse);

    final lina = await env.auth.signIn(
      email: 'lina@siz.app',
      password: DemoSeeder.clientPassword,
    );
    expect(lina.role, AccountRole.client);
    final visits = await env.activity.myVisits(lina.id);
    expect(visits, hasLength(4));
    expect(visits.where((v) => v.stars == null), hasLength(1));
    expect(await env.activity.myBookings(lina.id), hasLength(2));
    expect(await env.activity.favorites(lina.id), hasLength(2));

    final adam = await env.auth.signIn(
      email: 'adam@siz.app',
      password: DemoSeeder.clientPassword,
    );
    expect((await env.activity.mySpot(adam.id))?.shopName, 'Blade & Crown');

    // Sami: linked to his account, rated from visits, with photos.
    final sami = await env.auth.signIn(
      email: 'sami@siz.app',
      password: DemoSeeder.barberPassword,
    );
    final link = (await env.links.myLink(sami.id))!;
    expect(link.shopName, 'Blade & Crown');
    final portfolio = LocalPortfolioRepository(env.db);
    final rating = await portfolio.visitRatingOf(link.barberId);
    expect(rating.count, 3);
    expect(rating.average, 5);
    expect(await portfolio.postsOf(link.barberId), hasLength(2));
    expect(await LocalClientDirectory(env.db).latestPosts(), hasLength(6));
  });

  test('is idempotent', () async {
    await seeder.ensureDemoAccount();
    await seeder.ensureDemoAccount();
    final db = await env.db.database;
    expect(await db.query('owners'), hasLength(7));
    expect(await db.query('shops'), hasLength(3));
  });
}
