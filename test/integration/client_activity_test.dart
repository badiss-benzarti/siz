import 'package:flutter_test/flutter_test.dart';
import 'package:siz/core/auth/account_auth.dart';
import 'package:siz/core/errors/app_exception.dart';
import 'package:siz/features/barber_app/portfolio.dart';
import 'package:siz/features/client_app/client_activity.dart';
import 'package:siz/features/client_app/client_directory.dart';
import 'package:siz/features/finance/domain/service_ticket.dart';

import '../helpers/test_database.dart';

void main() {
  late TestEnv env;
  late ShopFixture f;
  late AppUser lina;

  setUp(() async {
    env = await TestEnv.create();
    f = await env.seedShop();
    lina = await env.auth.signUp(
      email: 'lina@test.tn',
      password: 'password123',
      fullName: 'Lina',
      role: AccountRole.client,
    );
  });
  tearDown(() => env.dispose());

  test(
    'clients see listed salons with their line, and not hidden ones',
    () async {
      final directory = LocalClientDirectory(env.db);
      await env.queue.addToQueue(shopId: f.shopId, clientName: 'Omar');
      final salons = await directory.salons();
      expect(salons.single.name, 'Blade');
      expect(salons.single.waitingCount, 1);
      expect(salons.single.load, SalonLoad.available);

      // Never who sits in a chair.
      await env.floor.seatClient(
        shopId: f.shopId,
        chairNumber: 1,
        clientName: 'Aziz',
      );
      final details = await directory.salon(f.shopId);
      expect(details.stations.first.activeBarberName, 'Sam');
      expect(details.stations.every((s) => s.activeClientName == null), isTrue);

      await env.shops.setShopListed(shopId: f.shopId, isListed: false);
      expect(await directory.salons(), isEmpty);
    },
  );

  test('the waiting line: one at a time, open salons only', () async {
    await env.activity.joinQueue(client: lina, shopId: f.shopId);
    final spot = await env.activity.mySpot(lina.id);
    expect(spot?.position, 1);
    expect(spot?.shopName, 'Blade');
    expect(
      (await env.queue.getWaitingQueue(f.shopId)).single.clientName,
      'Lina',
    );

    await expectLater(
      env.activity.joinQueue(client: lina, shopId: f.shopId),
      throwsA(isA<AppException>()),
    );

    await env.activity.leaveQueue(lina.id);
    expect(await env.activity.mySpot(lina.id), isNull);

    await env.shops.setShopOpen(shopId: f.shopId, isOpen: false);
    await expectLater(
      env.activity.joinQueue(client: lina, shopId: f.shopId),
      throwsA(isA<AppException>()),
    );
  });

  test('a visit from the line is linked to the client, who rates it', () async {
    await env.activity.joinQueue(client: lina, shopId: f.shopId);
    final item = (await env.queue.getWaitingQueue(f.shopId)).single;
    await env.floor.seatClient(
      shopId: f.shopId,
      chairNumber: 1,
      clientName: item.clientName,
      queueItemId: item.id,
    );
    final ticket = await env.floor.checkoutService(
      shopId: f.shopId,
      chairNumber: 1,
      serviceIds: [f.serviceId('Haircut')],
      paymentMethod: PaymentMethod.card,
    );

    final visits = await env.activity.myVisits(lina.id);
    expect(visits.single.ticketId, ticket.id);
    expect(visits.single.barberName, 'Sam');
    expect(visits.single.stars, isNull);

    await env.activity.rateVisit(
      clientId: lina.id,
      ticketId: ticket.id,
      stars: 4,
    );
    await env.activity.rateVisit(
      clientId: lina.id,
      ticketId: ticket.id,
      stars: 5,
    );
    expect((await env.activity.myVisits(lina.id)).single.stars, 5);

    // The barber's rating is made of visit ratings.
    final rating = await LocalPortfolioRepository(env.db)
        .visitRatingOf(f.barberId);
    expect(rating.average, 5);
    expect(rating.count, 1);
    final barbers = (await LocalClientDirectory(env.db).salon(f.shopId))
        .barbers;
    expect(barbers.single.ratingAvg, 5);

    // Only one's own visits, 1 to 5 stars.
    final adam = await env.auth.signUp(
      email: 'adam@test.tn',
      password: 'password123',
      fullName: 'Adam',
      role: AccountRole.client,
    );
    await expectLater(
      env.activity.rateVisit(clientId: adam.id, ticketId: ticket.id, stars: 1),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      env.activity.rateVisit(clientId: lina.id, ticketId: ticket.id, stars: 6),
      throwsA(isA<AppException>()),
    );
  });

  group('bookings', () {
    DateTime tomorrowAt(int hour) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day + 1, hour);
    }

    Future<Booking> book(AppUser who, DateTime at, {String? barberId}) =>
        env.activity.book(
          client: who,
          shopId: f.shopId,
          barberId: barberId,
          serviceName: 'Haircut',
          durationMinutes: 30,
          startsAt: at,
        );

    test('no double booking of a barber or a client', () async {
      final adam = await env.auth.signUp(
        email: 'adam@test.tn',
        password: 'password123',
        fullName: 'Adam',
        role: AccountRole.client,
      );
      final b = await book(lina, tomorrowAt(10), barberId: f.barberId);
      expect(b.status, BookingStatus.pending);
      expect(b.barberName, 'Sam');

      // Same barber, overlapping time.
      await expectLater(
        book(
          adam,
          tomorrowAt(10).add(const Duration(minutes: 15)),
          barberId: f.barberId,
        ),
        throwsA(isA<AppException>()),
      );
      // Right after is fine.
      await book(
        adam,
        tomorrowAt(10).add(const Duration(minutes: 30)),
        barberId: f.barberId,
      );
      // The same client twice at once, even with "any barber".
      await expectLater(
        book(lina, tomorrowAt(10)),
        throwsA(isA<AppException>()),
      );

      // A cancelled slot is free again.
      await env.activity.cancelBooking(b.id, lina.id);
      final again = await book(lina, tomorrowAt(10), barberId: f.barberId);
      expect(again.status, BookingStatus.pending);
    });

    test('refuses the past and too far ahead', () async {
      await expectLater(
        book(lina, DateTime.now().subtract(const Duration(hours: 1))),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        book(lina, DateTime.now().add(const Duration(days: 40))),
        throwsA(isA<AppException>()),
      );
    });

    test('the salon accepts, then checks the client in to the line', () async {
      final b = await book(lina, DateTime.now().add(const Duration(hours: 1)));
      expect((await env.activity.shopBookings(f.shopId)).single.id, b.id);
      expect(
        (await env.activity.barberBookings(f.shopId, f.barberId)).single.id,
        b.id,
      );

      await env.activity.answerBooking(b.id, accept: true);
      await expectLater(
        env.activity.answerBooking(b.id, accept: false),
        throwsA(isA<AppException>()),
      );
      await env.activity.checkIn(b.id);

      expect(
        (await env.activity.myBookings(lina.id)).single.status,
        BookingStatus.done,
      );
      final waiting = await env.queue.getWaitingQueue(f.shopId);
      expect(waiting.single.clientName, 'Lina');
      expect((await env.activity.mySpot(lina.id))?.position, 1);
    });

    test('declined bookings cannot be checked in', () async {
      final b = await book(lina, tomorrowAt(11));
      await env.activity.answerBooking(b.id, accept: false);
      await expectLater(
        env.activity.checkIn(b.id),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        env.activity.cancelBooking(b.id, lina.id),
        throwsA(isA<AppException>()),
      );
    });
  });

  test('favorites, photo ratings and comments', () async {
    expect(await env.activity.toggleFavorite(lina.id, f.shopId), isTrue);
    expect((await env.activity.favorites(lina.id)).single.name, 'Blade');
    expect(await env.activity.toggleFavorite(lina.id, f.shopId), isFalse);
    expect(await env.activity.favorites(lina.id), isEmpty);

    final db = await env.db.database;
    await db.insert('portfolio_posts', {
      'id': 'p1',
      'barber_id': f.barberId,
      'shop_id': f.shopId,
      'image': 'art:fade',
      'caption': 'Fade',
      'created_at': DateTime.now().toIso8601String(),
    });
    await env.activity.ratePhoto(clientId: lina.id, postId: 'p1', stars: 4);
    await env.activity.comment(author: lina, postId: 'p1', body: ' Nice! ');
    await expectLater(
      env.activity.comment(author: lina, postId: 'p1', body: '   '),
      throwsA(isA<AppException>()),
    );

    expect(await env.activity.myPhotoRating(lina.id, 'p1'), 4);
    final post = (await LocalClientDirectory(env.db).latestPosts()).single;
    expect(post.ratingAvg, 4);
    expect(post.commentCount, 1);
    expect(post.barberName, 'Sam');
    final comments = await LocalClientDirectory(env.db).comments('p1');
    expect(comments.single.body, 'Nice!');

    // Photo stars do not count in the barber's rating.
    final rating = await LocalPortfolioRepository(env.db)
        .visitRatingOf(f.barberId);
    expect(rating.count, 0);
  });
}
