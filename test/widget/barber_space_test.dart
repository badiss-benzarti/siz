import 'package:siz/core/cloud/cloud_auth.dart';
import 'package:siz/core/providers/cloud_providers.dart';
import 'package:siz/core/theme/app_theme.dart';
import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/barber_app/barber_earnings.dart';
import 'package:siz/features/barber_app/barber_link.dart';
import 'package:siz/features/barber_app/barber_salon.dart';
import 'package:siz/features/barber_app/barber_screens.dart';
import 'package:siz/features/barber_app/portfolio.dart';
import 'package:siz/features/finance/domain/service_ticket.dart';
import 'package:siz/features/floor_plan/domain/station.dart';
import 'package:siz/features/queue/domain/queue_item.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud_auth.dart';

class _Links implements BarberLinkRepository {
  BarberLink link = _sami(onDuty: true);

  @override
  Future<BarberLink?> myLink(String userId) async => link;

  @override
  Future<BarberLink> join(String userId, String code) =>
      throw UnimplementedError();

  @override
  Future<InvitePreview?> preview(String code) => throw UnimplementedError();

  @override
  Future<void> requestNameChange(String name) => throw UnimplementedError();

  @override
  Future<void> leave() => throw UnimplementedError();
}

class _Salon implements BarberSalonRepository {
  _Salon(this.links);

  final _Links links;
  final walkIns = <String>[];

  @override
  Future<SalonFloor> load(String shopId) async => SalonFloor(
    shopName: 'Blade & Crown',
    established: 2026,
    totalChairs: 4,
    isOpen: true,
    stations: [
      Station(
        chairNumber: 1,
        shopId: shopId,
        status: links.link.isOnDuty ? ChairStatus.available : ChairStatus.empty,
        activeBarberId: links.link.isOnDuty ? 'b1' : null,
        activeBarberName: links.link.isOnDuty ? 'Sami' : null,
      ),
      Station(
        chairNumber: 2,
        shopId: shopId,
        status: ChairStatus.occupied,
        activeBarberId: 'b2',
        activeBarberName: 'Karim',
        activeClientName: 'Omar',
        serviceStartTime: DateTime.now().subtract(const Duration(minutes: 9)),
      ),
      Station(chairNumber: 3, shopId: shopId),
      Station(chairNumber: 4, shopId: shopId),
    ],
    queue: [
      QueueItem(
        id: 'q1',
        shopId: shopId,
        clientName: 'Aziz',
        requestedBarberId: 'b1',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      QueueItem(
        id: 'q2',
        shopId: shopId,
        clientName: 'Hamza',
        createdAt: DateTime.now(),
      ),
      for (final name in walkIns)
        QueueItem(
          id: name,
          shopId: shopId,
          clientName: name,
          createdAt: DateTime.now(),
        ),
    ],
  );

  @override
  Future<void> setMyDuty({required bool onDuty}) async =>
      links.link = _sami(onDuty: onDuty);

  @override
  Future<void> addWalkIn(String shopId, String clientName) async =>
      walkIns.add(clientName);
}

class _Earnings implements BarberEarningsRepository {
  @override
  Future<List<EarningLine>> since(String barberId, DateTime from) async => [
    EarningLine(
      time: DateTime.now().subtract(const Duration(minutes: 30)),
      clientName: 'Omar',
      services: 'Haircut',
      commission: 15,
      tip: 2,
      paymentMethod: PaymentMethod.cash,
      chairNumber: 1,
    ),
  ];
}

class _Portfolio implements PortfolioRepository {
  final deleted = <String>[];

  @override
  Future<List<PortfolioPost>> postsOf(String barberId) async => [
    for (final (id, stars, count) in [('p1', 4.5, 2), ('p2', 0.0, 0)])
      if (!deleted.contains(id))
        PortfolioPost(
          id: id,
          imagePath: 'b1/$id.jpg',
          imageUrl: 'https://example.test/$id.jpg',
          caption: id == 'p1' ? 'Mid skin fade' : '',
          ratingAvg: stars,
          ratingCount: count,
          commentCount: id == 'p1' ? 1 : 0,
          createdAt: DateTime(2026, 10, 8, 12),
        ),
  ];

  @override
  Future<List<PostComment>> commentsOf(String postId) async => [
    PostComment(
      id: 'c1',
      authorName: 'Chedi',
      body: 'Clean work',
      createdAt: DateTime(2026, 10, 8, 13),
    ),
  ];

  @override
  Future<VisitRating> visitRatingOf(String barberId) async =>
      const VisitRating(4.8, 12);

  @override
  Future<void> publish({
    required String barberId,
    required Uint8List photo,
    required String caption,
  }) async {}

  @override
  Future<void> deletePost(PortfolioPost post) async => deleted.add(post.id);

  @override
  Future<void> deleteComment(String commentId) async {}
}

BarberLink _sami({required bool onDuty}) => BarberLink(
  barberId: 'b1',
  barberName: 'Sami',
  shopId: 's1',
  shopName: 'Blade & Crown',
  commissionRate: 0.6,
  isOnDuty: onDuty,
  assignedChair: onDuty ? 1 : null,
);

void main() {
  testWidgets('a barber sees the floor, the queue and switches duty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final auth = FakeCloudAuth()
      ..currentUser = const CloudUser(
        id: 'u1',
        email: 'sami@test.tn',
        fullName: 'Sami',
        role: AccountRole.barber,
      );
    final links = _Links();
    final salon = _Salon(links);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudAuthProvider.overrideWithValue(auth),
          barberLinkRepositoryProvider.overrideWithValue(links),
          barberSalonRepositoryProvider.overrideWithValue(salon),
          barberEarningsRepositoryProvider.overrideWithValue(_Earnings()),
          portfolioRepositoryProvider.overrideWithValue(_Portfolio()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const BarberGate(),
        ),
      ),
    );
    // The salon sign animates forever: pump instead of settling.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Salon tab: the live floor, with barbers on the chairs.
    expect(find.textContaining('#1 · Sami'), findsOneWidget);
    expect(find.textContaining('#2 · Karim'), findsOneWidget);
    expect(find.text('2 clients waiting'), findsOneWidget);

    // Earnings: today's commission and tips, only his own.
    await tester.tap(find.text('Earnings'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('My Earnings'), findsOneWidget);
    expect(find.text('TODAY · YOU EARNED'), findsOneWidget);
    expect(find.text('Omar'), findsOneWidget);
    expect(find.text('Tip ${formatMoney(2)}'), findsOneWidget);

    // Agenda: my chair, the queue, who asked for me.
    await tester.tap(find.text('Agenda'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('My Agenda'), findsOneWidget);
    expect(find.text('Waiting (2)'), findsOneWidget);
    expect(find.text('Asked for you'), findsOneWidget);
    expect(find.text('On duty'), findsOneWidget);

    // Off duty: the chair is released.
    await tester.tap(find.byType(Switch));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Off duty'), findsOneWidget);
    expect(find.textContaining('No chair yet'), findsOneWidget);

    // Portfolio: a social profile, visit rating apart from photo stars.
    await tester.tap(find.text('Portfolio'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('My Portfolio'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('12 visits'), findsOneWidget);
    // The photos average in the header, and the rated photo in the grid.
    expect(find.text('4.5'), findsNWidgets(2));

    // A post: caption, its own stars, clients' comments.
    await tester.tap(find.text('4.5').last);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Mid skin fade'), findsOneWidget);
    expect(find.text('4.5 · 2 ratings'), findsOneWidget);
    expect(find.text('Clean work'), findsOneWidget);
  });
}
