import 'dart:math';

import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../media/haircut_art.dart';
import '../media/local_photo.dart';
import '../repositories/floor_plan_repository.dart';
import '../repositories/queue_repository.dart';
import '../repositories/shop_repository.dart';
import '../security/password_hasher.dart';
import '../../features/auth_onboarding/domain/shop_profile.dart';
import '../../features/barbers/domain/barber.dart';
import '../../features/finance/domain/service_ticket.dart';

/// A ready-made account of the demo, shown on the welcome screen.
class DemoAccount {
  const DemoAccount(this.role, this.name, this.email, this.password, this.note);

  /// 'owner', 'barber' or 'client'.
  final String role;
  final String name;
  final String email;
  final String password;
  final String note;
}

/// Creates the demo on this device: the "Blade & Crown" salon fully
/// populated (barbers, services, a month of sales, cuts in progress, clients
/// waiting), two more salons, barber and client accounts, visits and their
/// ratings, portfolio photos with comments, bookings and favorites.
class DemoSeeder {
  DemoSeeder({
    required this._dbService,
    required this._shops,
    required this._floor,
    required this._queue,
    this._hasher = const PasswordHasher(),
  });

  final DatabaseService _dbService;
  final ShopRepository _shops;
  final FloorPlanRepository _floor;
  final QueueRepository _queue;
  final PasswordHasher _hasher;
  final _uuid = const Uuid();

  static const String email = 'demo@barbershop.app';
  static const String password = 'Demo2026!';

  static const barberPassword = 'Barber2026!';
  static const clientPassword = 'Client2026!';
  static const ownerPassword = 'Owner2026!';

  /// Every account the demo creates, for one-tap sign-in.
  static const accounts = [
    DemoAccount('owner', 'Demo Owner', email, password, 'Blade & Crown'),
    DemoAccount(
      'barber',
      'Sami',
      'sami@siz.app',
      barberPassword,
      'Barber at Blade & Crown',
    ),
    DemoAccount(
      'barber',
      'Karim',
      'karim@siz.app',
      barberPassword,
      'Barber at Blade & Crown',
    ),
    DemoAccount(
      'client',
      'Lina Ben Salah',
      'lina@siz.app',
      clientPassword,
      'Has visits, bookings and favorites',
    ),
    DemoAccount(
      'client',
      'Adam Gharbi',
      'adam@siz.app',
      clientPassword,
      'Waiting in line at Blade & Crown',
    ),
    DemoAccount(
      'owner',
      'Mehdi Zouari',
      'mehdi@siz.app',
      ownerPassword,
      'Fade Factory',
    ),
  ];

  static const _historyDays = 30;

  static const _clients = [
    ('Omar Ben Ali', '+216 22 145 870'),
    ('Mehdi Trabelsi', '+216 55 301 442'),
    ('Aziz Gharbi', '+216 98 774 120'),
    ('Yassine Jlassi', null),
    ('Hamza Chaabane', '+216 23 889 016'),
    ('Firas Mansour', null),
    ('Anis Khelifi', '+216 52 610 339'),
    ('Skander Bouazizi', '+216 97 452 781'),
    ('Rami Hammami', null),
    ('Walid Ayari', '+216 21 507 964'),
    ('Nizar Sassi', null),
    ('Bilel Mejri', '+216 29 336 105'),
    ('Karim Dridi', '+216 94 218 670'),
    ('Seif Riahi', null),
    ('Malek Zouari', '+216 50 993 214'),
    ('Adam Belhadj', null),
  ];

  /// Creates the demo account if it does not exist yet. Safe to call
  /// repeatedly.
  Future<void> ensureDemoAccount() async {
    final db = await _dbService.database;
    final existing = await db.query(
      'owners',
      columns: ['id'],
      where: 'email = ?',
      whereArgs: [email],
    );
    if (existing.isNotEmpty) return;

    final owner = await _shops.registerOwner(
      email: email,
      password: password,
      fullName: 'Demo Owner',
    );
    final shop = await populateShop(owner.id);
    await _seedCommunity(shop);
  }

  /// Creates the demo salon for [ownerId] and fills it: team, prices, a
  /// month of sales, two cuts in progress and three clients waiting.
  Future<ShopProfile> populateShop(String ownerId) async {
    final db = await _dbService.database;
    final now = DateTime.now();
    Barber barber(String name, String phone, double rate, int? chair) => Barber(
      id: _uuid.v4(),
      shopId: '',
      name: name,
      phone: phone,
      commissionRate: rate,
      assignedChair: chair,
      createdAt: now,
    );

    final team = [
      barber('Sami', '+216 20 111 222', 0.60, 1),
      barber('Karim', '+216 20 333 444', 0.55, 3),
      barber('Youssef', '+216 20 555 666', 0.50, 6),
      barber('Nour', '+216 20 777 888', 0.60, 7),
      barber('Ali', '+216 20 999 000', 0.50, null),
    ];

    final shop = await _shops.setupShopProfile(
      ownerId: ownerId,
      name: 'Blade & Crown',
      address: 'Avenue Habib Bourguiba, Tunis',
      phone: '+216 71 234 567',
      totalChairs: 8,
      initialBarbers: team,
      services: const [
        ServiceItem(id: '', shopId: '', name: 'Haircut', price: 25),
        ServiceItem(
          id: '',
          shopId: '',
          name: 'Beard Trim',
          price: 15,
          durationMinutes: 20,
        ),
        ServiceItem(
          id: '',
          shopId: '',
          name: 'Haircut + Beard',
          price: 35,
          durationMinutes: 45,
        ),
        ServiceItem(
          id: '',
          shopId: '',
          name: 'Kids Haircut',
          price: 20,
          durationMinutes: 25,
        ),
        ServiceItem(
          id: '',
          shopId: '',
          name: 'Hot Towel Shave',
          price: 18,
          durationMinutes: 25,
        ),
        ServiceItem(
          id: '',
          shopId: '',
          name: 'Hair Wash',
          price: 10,
          durationMinutes: 10,
        ),
      ],
    );

    // Ali is on the roster but off duty today.
    await db.update(
      'barbers',
      {'is_on_duty': 0},
      where: 'id = ?',
      whereArgs: [team.last.id],
    );

    await _insertHistory(shop, team.take(4).toList(), now);
    await _setLiveFloor(shop.id, now);
    return shop;
  }

  /// A month of completed sales, deterministic so the demo looks the same
  /// on every device.
  Future<void> _insertHistory(
    ShopProfile shop,
    List<Barber> barbers,
    DateTime now, {
    int days = _historyDays,
    int seed = 2026,
  }) async {
    final random = Random(seed);
    final services = shop.services;
    final db = await _dbService.database;
    final batch = db.batch();
    final today = DateTime(now.year, now.month, now.day);

    for (var dayOffset = days; dayOffset >= 0; dayOffset--) {
      final day = today.subtract(Duration(days: dayOffset));
      final isWeekend = day.weekday >= DateTime.friday;
      final count = (isWeekend ? 11 : 6) + random.nextInt(6);

      for (var i = 0; i < count; i++) {
        final minutes = 9 * 60 + random.nextInt(10 * 60);
        final time = day.add(Duration(minutes: minutes));
        if (!time.isBefore(now.subtract(const Duration(minutes: 30)))) {
          continue; // Nothing in the future for today.
        }

        final barber = barbers[random.nextInt(barbers.length)];
        final chair = barber.assignedChair ?? 2;
        final picked = <ServiceItem>{services[random.nextInt(services.length)]};
        if (random.nextDouble() < 0.3) {
          picked.add(services[random.nextInt(services.length)]);
        }
        final subtotal = picked.fold<double>(0, (s, e) => s + e.price);
        final barberCut = FloorPlanRepository.roundMoney(
          subtotal * barber.commissionRate,
        );
        final tipRoll = random.nextDouble();
        final tip = tipRoll < 0.55
            ? 0.0
            : FloorPlanRepository.roundMoney(
                subtotal * (tipRoll < 0.85 ? 0.10 : 0.15),
              );
        final payRoll = random.nextDouble();
        final client = _clients[random.nextInt(_clients.length)];

        batch.insert(
          'tickets',
          ServiceTicket(
            id: _uuid.v4(),
            shopId: shop.id,
            clientName: client.$1,
            clientPhone: client.$2,
            barberId: barber.id,
            chairNumber: chair,
            serviceNames: picked.map((s) => s.name).toList(),
            totalPrice: subtotal,
            barberCut: barberCut,
            shopCut: FloorPlanRepository.roundMoney(subtotal - barberCut),
            tip: tip,
            paymentMethod: payRoll < 0.6
                ? PaymentMethod.cash
                : PaymentMethod.card,
            timestamp: time,
          ).toMap(),
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// Two cuts in progress and three clients on the waiting couch.
  Future<void> _setLiveFloor(String shopId, DateTime now) async {
    final db = await _dbService.database;
    for (final (chair, client, minutesAgo) in const [
      (3, 'Omar Ben Ali', 12),
      (6, 'Mehdi Trabelsi', 25),
    ]) {
      await _floor.seatClient(
        shopId: shopId,
        chairNumber: chair,
        clientName: client,
      );
      await db.update(
        'chairs',
        {
          'service_start_time': now
              .subtract(Duration(minutes: minutesAgo))
              .toIso8601String(),
        },
        where: 'shop_id = ? AND chair_number = ?',
        whereArgs: [shopId, chair],
      );
    }

    for (final (name, phone) in const [
      ('Aziz Gharbi', '+216 98 774 120'),
      ('Hamza Chaabane', '+216 23 889 016'),
      ('Firas Mansour', null),
    ]) {
      await _queue.addToQueue(
        shopId: shopId,
        clientName: name,
        clientPhone: phone,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // The rest of the demo: accounts, other salons, social life
  // ---------------------------------------------------------------------------

  Future<String> _account(
    String email,
    String password,
    String name,
    String role,
  ) async {
    final db = await _dbService.database;
    final salt = _hasher.generateSalt();
    final id = _uuid.v4();
    await db.insert('owners', {
      'id': id,
      'email': email,
      'password_hash': await _hasher.hash(password, salt),
      'salt': salt,
      'full_name': name,
      'role': role,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> _seedCommunity(ShopProfile blade) async {
    final db = await _dbService.database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Barbers of Blade & Crown and what they are known for.
    final team = {
      for (final r in await db.query(
        'barbers',
        where: 'shop_id = ?',
        whereArgs: [blade.id],
      ))
        r['name'] as String: r['id'] as String,
    };
    for (final (name, specialty) in const [
      ('Sami', 'Skin fades'),
      ('Karim', 'Beards & classic cuts'),
      ('Youssef', 'Kids cuts'),
      ('Nour', 'Curly hair'),
      ('Ali', 'Hot towel shaves'),
    ]) {
      await db.update(
        'barbers',
        {'specialty': specialty},
        where: 'id = ?',
        whereArgs: [team[name]],
      );
    }

    // Barber accounts, linked to their roster entry.
    for (final (name, mail) in const [
      ('Sami', 'sami@siz.app'),
      ('Karim', 'karim@siz.app'),
    ]) {
      final id = await _account(mail, barberPassword, name, 'barber');
      await db.update(
        'barbers',
        {'profile_id': id},
        where: 'id = ?',
        whereArgs: [team[name]],
      );
    }

    // Client accounts.
    final lina = await _account(
      'lina@siz.app',
      clientPassword,
      'Lina Ben Salah',
      'client',
    );
    final adam = await _account(
      'adam@siz.app',
      clientPassword,
      'Adam Gharbi',
      'client',
    );

    // Two more salons.
    final mehdi = await _account(
      'mehdi@siz.app',
      ownerPassword,
      'Mehdi Zouari',
      'owner',
    );
    final fade = await _otherSalon(
      ownerId: mehdi,
      name: 'Fade Factory',
      address: 'Rue du Lac Biwa, Les Berges du Lac',
      phone: '+216 71 960 300',
      chairs: 6,
      barbers: const [('Rayen', 'Fades & designs'), ('Hedi', 'Long hair')],
      waiting: const ['Oussama', 'Wassim', 'Ilyes', 'Moez', 'Zied'],
      seed: 7,
    );
    final gentOwner = await _account(
      'gentlemen@siz.app',
      ownerPassword,
      'Slim Ayari',
      'owner',
    );
    final gentlemen = await _otherSalon(
      ownerId: gentOwner,
      name: "The Gentlemen's Room",
      address: 'Avenue de Carthage, La Marsa',
      phone: '+216 71 774 515',
      chairs: 4,
      barbers: const [('Fares', 'Classic cuts')],
      waiting: const [],
      seed: 11,
    );
    await db.update(
      'shops',
      {'is_open': 0},
      where: 'id = ?',
      whereArgs: [gentlemen.id],
    );

    // Visits of the client accounts at Blade & Crown, most of them rated.
    // These ratings are the barbers' ratings.
    final services = blade.services;
    var n = 0;
    for (final (client, clientName, barber, daysAgo, stars) in [
      (lina, 'Lina Ben Salah', 'Sami', 26, 5),
      (lina, 'Lina Ben Salah', 'Sami', 12, 5),
      (lina, 'Lina Ben Salah', 'Nour', 5, 4),
      (lina, 'Lina Ben Salah', 'Sami', 1, null),
      (adam, 'Adam Gharbi', 'Karim', 20, 4),
      (adam, 'Adam Gharbi', 'Sami', 9, 5),
      (adam, 'Adam Gharbi', 'Karim', 3, 5),
      (adam, 'Adam Gharbi', 'Youssef', 2, 3),
    ]) {
      final service = services[n++ % services.length];
      final rows = await db.query(
        'barbers',
        columns: ['commission_rate', 'assigned_chair'],
        where: 'id = ?',
        whereArgs: [team[barber]],
      );
      final rate = (rows.first['commission_rate'] as num).toDouble();
      final cut = FloorPlanRepository.roundMoney(service.price * rate);
      final ticketId = _uuid.v4();
      final time = today
          .subtract(Duration(days: daysAgo))
          .add(Duration(hours: 10 + n % 7, minutes: 15));
      await db.insert('tickets', {
        ...ServiceTicket(
          id: ticketId,
          shopId: blade.id,
          clientName: clientName,
          barberId: team[barber]!,
          chairNumber: (rows.first['assigned_chair'] as int?) ?? 2,
          serviceNames: [service.name],
          totalPrice: service.price,
          barberCut: cut,
          shopCut: FloorPlanRepository.roundMoney(service.price - cut),
          paymentMethod: n.isEven ? PaymentMethod.cash : PaymentMethod.card,
          timestamp: time,
        ).toMap(),
        'client_id': client,
      });
      if (stars != null) {
        await db.insert('visit_ratings', {
          'ticket_id': ticketId,
          'barber_id': team[barber],
          'client_id': client,
          'stars': stars,
          'created_at': time.add(const Duration(hours: 2)).toIso8601String(),
        });
      }
    }

    // Portfolio photos (drawn, so no sample files are needed).
    final posts = <String>[];
    for (final (shopId, barberId, style, caption, daysAgo) in [
      (
        blade.id,
        team['Sami']!,
        HaircutStyle.fade,
        'Mid skin fade, sharp line-up',
        1,
      ),
      (
        blade.id,
        team['Karim']!,
        HaircutStyle.beard,
        'Full beard sculpt + hot towel',
        2,
      ),
      (
        blade.id,
        team['Nour']!,
        HaircutStyle.curly,
        'Defined curls, tapered sides',
        4,
      ),
      (blade.id, team['Sami']!, HaircutStyle.pompadour, 'Modern pompadour', 6),
      (
        fade.id,
        fade.barberIds.first,
        HaircutStyle.crop,
        'Textured French crop',
        3,
      ),
      (
        blade.id,
        team['Karim']!,
        HaircutStyle.buzz,
        'Clean buzz cut, number 2',
        9,
      ),
    ]) {
      final id = _uuid.v4();
      posts.add(id);
      await db.insert('portfolio_posts', {
        'id': id,
        'barber_id': barberId,
        'shop_id': shopId,
        'image': '${PhotoStore.artPrefix}${style.name}',
        'caption': caption,
        'created_at': now
            .subtract(Duration(days: daysAgo, hours: 3))
            .toIso8601String(),
      });
    }
    for (final (post, author, authorName, body) in [
      (posts[0], lina, 'Lina Ben Salah', 'So clean! Booking you next week.'),
      (posts[0], adam, 'Adam Gharbi', 'Best fade in town.'),
      (posts[1], adam, 'Adam Gharbi', 'That beard line is perfect.'),
      (posts[2], lina, 'Lina Ben Salah', 'Love the curls.'),
    ]) {
      await db.insert('post_comments', {
        'id': _uuid.v4(),
        'post_id': post,
        'author_id': author,
        'author_name': authorName,
        'body': body,
        'created_at': now.subtract(const Duration(hours: 5)).toIso8601String(),
      });
    }
    for (final (post, client, stars) in [
      (posts[0], lina, 5),
      (posts[0], adam, 5),
      (posts[1], adam, 4),
      (posts[2], lina, 5),
      (posts[3], adam, 4),
      (posts[4], lina, 4),
    ]) {
      await db.insert('photo_ratings', {
        'post_id': post,
        'client_id': client,
        'stars': stars,
      });
    }

    // Adam waits in line; Lina has bookings and favorites.
    await _queue.addToQueue(
      shopId: blade.id,
      clientName: 'Adam Gharbi',
      clientId: adam,
      requestedBarberId: team['Sami'],
    );
    final soon = DateTime(now.year, now.month, now.day, now.hour + 2);
    final confirmedAt = soon.hour <= 19
        ? soon
        : today.add(const Duration(days: 1, hours: 11));
    final tomorrow = today.add(const Duration(days: 1));
    for (final (client, barber, service, minutes, at, status) in [
      (lina, team['Sami'], 'Haircut', 30, confirmedAt, 'accepted'),
      (
        lina,
        team['Nour'],
        'Haircut + Beard',
        45,
        tomorrow.add(const Duration(days: 2, hours: 16)),
        'pending',
      ),
      (
        adam,
        team['Karim'],
        'Beard Trim',
        20,
        tomorrow.add(const Duration(hours: 15)),
        'pending',
      ),
    ]) {
      await db.insert('bookings', {
        'id': _uuid.v4(),
        'shop_id': blade.id,
        'client_id': client,
        'barber_id': barber,
        'service_name': service,
        'duration_minutes': minutes,
        'starts_at': at.toIso8601String(),
        'status': status,
        'created_at': now.toIso8601String(),
      });
    }
    for (final shopId in [blade.id, fade.id]) {
      await db.insert('favorites', {
        'client_id': lina,
        'shop_id': shopId,
        'created_at': now.toIso8601String(),
      });
    }
  }

  /// A smaller salon: a few barbers, the usual services, two weeks of sales
  /// and its own waiting line.
  Future<({String id, List<String> barberIds})> _otherSalon({
    required String ownerId,
    required String name,
    required String address,
    required String phone,
    required int chairs,
    required List<(String, String)> barbers,
    required List<String> waiting,
    required int seed,
  }) async {
    final now = DateTime.now();
    final team = [
      for (final (i, (barberName, _)) in barbers.indexed)
        Barber(
          id: _uuid.v4(),
          shopId: '',
          name: barberName,
          phone: '+216 20 000 00$i',
          commissionRate: 0.55,
          assignedChair: i + 1,
          createdAt: now,
        ),
    ];
    final shop = await _shops.setupShopProfile(
      ownerId: ownerId,
      name: name,
      address: address,
      phone: phone,
      totalChairs: chairs,
      initialBarbers: team,
      services: const [
        ServiceItem(id: '', shopId: '', name: 'Haircut', price: 22),
        ServiceItem(
          id: '',
          shopId: '',
          name: 'Fade',
          price: 28,
          durationMinutes: 40,
        ),
        ServiceItem(
          id: '',
          shopId: '',
          name: 'Beard Trim',
          price: 12,
          durationMinutes: 20,
        ),
      ],
    );
    final db = await _dbService.database;
    for (final (i, (_, specialty)) in barbers.indexed) {
      await db.update(
        'barbers',
        {'specialty': specialty},
        where: 'id = ?',
        whereArgs: [team[i].id],
      );
    }
    await _insertHistory(shop, team, now, days: 14, seed: seed);
    for (final client in waiting) {
      await _queue.addToQueue(shopId: shop.id, clientName: client);
    }
    return (id: shop.id, barberIds: [for (final b in team) b.id]);
  }
}
