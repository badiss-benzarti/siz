import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/account_auth.dart';
import '../../core/database/database_service.dart';
import '../../core/errors/app_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../core/providers/data_revision.dart';
import 'client_directory.dart';
import 'client_session.dart';

/// A client's place in a salon's waiting line.
class QueueSpot {
  const QueueSpot({
    required this.queueId,
    required this.shopId,
    required this.shopName,
    required this.position,
    required this.joinedAt,
  });

  final String queueId;
  final String shopId;
  final String shopName;

  /// 1 = next in line.
  final int position;
  final DateTime joinedAt;
}

enum BookingStatus {
  pending,
  accepted,
  declined,
  cancelled,
  done;

  static BookingStatus parse(Object? v) =>
      values.asNameMap()[v] ?? BookingStatus.pending;

  String get label => switch (this) {
    pending => 'Waiting for the salon',
    accepted => 'Confirmed',
    declined => 'Declined',
    cancelled => 'Cancelled',
    done => 'Checked in',
  };
}

/// A booked time slot at a salon.
class Booking {
  const Booking({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.clientId,
    required this.clientName,
    required this.serviceName,
    required this.durationMinutes,
    required this.startsAt,
    required this.status,
    this.barberId,
    this.barberName,
  });

  final String id;
  final String shopId;
  final String shopName;
  final String clientId;
  final String clientName;
  final String? barberId;

  /// Null when the client lets the salon choose.
  final String? barberName;
  final String serviceName;
  final int durationMinutes;
  final DateTime startsAt;
  final BookingStatus status;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  bool get isActive =>
      status == BookingStatus.pending || status == BookingStatus.accepted;
}

/// A finished cut of a client, which they can rate.
class Visit {
  const Visit({
    required this.ticketId,
    required this.shopId,
    required this.shopName,
    required this.barberId,
    required this.barberName,
    required this.services,
    required this.total,
    required this.time,
    this.stars,
  });

  final String ticketId;
  final String shopId;
  final String shopName;
  final String barberId;
  final String barberName;
  final String services;
  final double total;
  final DateTime time;

  /// The client's rating, once given.
  final int? stars;
}

/// Everything a signed-in client does: favorites, the waiting line,
/// bookings, rating visits and photos, commenting. Owners and barbers use
/// the booking side to answer requests. Failures are thrown as
/// [AppException].
class ClientActivityRepository {
  ClientActivityRepository(this._db);

  final DatabaseService _db;
  final _uuid = const Uuid();

  /// Bookings can be made up to this far ahead.
  static const bookAhead = Duration(days: 30);

  // ---------------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------------

  Future<List<ClientSalon>> favorites(String clientId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '${SalonQuery.select} JOIN favorites f ON f.shop_id = s.id '
      'WHERE f.client_id = ? AND s.is_listed = 1 ORDER BY f.created_at DESC',
      [clientId],
    );
    return rows.map(SalonQuery.read).toList();
  }

  /// Adds or removes [shopId]; returns whether it is now a favorite.
  Future<bool> toggleFavorite(String clientId, String shopId) async {
    final db = await _db.database;
    final removed = await db.delete(
      'favorites',
      where: 'client_id = ? AND shop_id = ?',
      whereArgs: [clientId, shopId],
    );
    if (removed > 0) return false;
    await db.insert('favorites', {
      'client_id': clientId,
      'shop_id': shopId,
      'created_at': DateTime.now().toIso8601String(),
    });
    return true;
  }

  // ---------------------------------------------------------------------------
  // Waiting line
  // ---------------------------------------------------------------------------

  /// Where the client waits now, if anywhere.
  Future<QueueSpot?> mySpot(String clientId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT q.id, q.shop_id, q.created_at, s.name AS shop_name,
        (SELECT COUNT(*) FROM queue o
          WHERE o.shop_id = q.shop_id AND o.status = 'waiting'
            AND o.created_at <= q.created_at) AS position
      FROM queue q JOIN shops s ON s.id = q.shop_id
      WHERE q.client_id = ? AND q.status = 'waiting'
      LIMIT 1
    ''',
      [clientId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return QueueSpot(
      queueId: r['id'] as String,
      shopId: r['shop_id'] as String,
      shopName: r['shop_name'] as String,
      position: r['position'] as int,
      joinedAt: DateTime.parse(r['created_at'] as String),
    );
  }

  /// Puts the client at the end of the salon's line. One line at a time,
  /// and only while the salon is open.
  Future<void> joinQueue({
    required AppUser client,
    required String shopId,
    String? barberId,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final shop = await txn.query(
        'shops',
        columns: ['is_open', 'is_listed'],
        where: 'id = ?',
        whereArgs: [shopId],
      );
      if (shop.isEmpty || shop.first['is_listed'] != 1) {
        throw const AppException('This salon is not available.');
      }
      if (shop.first['is_open'] != 1) {
        throw const AppException('This salon is closed right now.');
      }
      final waiting = await txn.query(
        'queue',
        columns: ['id'],
        where: "client_id = ? AND status = 'waiting'",
        whereArgs: [client.id],
      );
      if (waiting.isNotEmpty) {
        throw const AppException(
          'You are already in a line. Leave it first to join another.',
        );
      }
      await txn.insert('queue', {
        'id': _uuid.v4(),
        'shop_id': shopId,
        'client_name': client.fullName,
        'client_id': client.id,
        'requested_barber_id': barberId,
        'status': 'waiting',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> leaveQueue(String clientId) async {
    final db = await _db.database;
    await db.delete(
      'queue',
      where: "client_id = ? AND status = 'waiting'",
      whereArgs: [clientId],
    );
  }

  // ---------------------------------------------------------------------------
  // Bookings
  // ---------------------------------------------------------------------------

  static const _bookingSelect = '''
    SELECT k.*, s.name AS shop_name, b.name AS barber_name,
      o.full_name AS client_name
    FROM bookings k
    JOIN shops s ON s.id = k.shop_id
    JOIN owners o ON o.id = k.client_id
    LEFT JOIN barbers b ON b.id = k.barber_id
  ''';

  static Booking _booking(Map<String, Object?> r) => Booking(
    id: r['id'] as String,
    shopId: r['shop_id'] as String,
    shopName: r['shop_name'] as String,
    clientId: r['client_id'] as String,
    clientName: r['client_name'] as String,
    barberId: r['barber_id'] as String?,
    barberName: r['barber_name'] as String?,
    serviceName: r['service_name'] as String,
    durationMinutes: r['duration_minutes'] as int,
    startsAt: DateTime.parse(r['starts_at'] as String),
    status: BookingStatus.parse(r['status']),
  );

  /// Asks the salon for a slot. Refused in the past, too far ahead, or when
  /// it overlaps another booking of the same barber or of the client.
  Future<Booking> book({
    required AppUser client,
    required String shopId,
    required String serviceName,
    required int durationMinutes,
    required DateTime startsAt,
    String? barberId,
  }) async {
    final now = DateTime.now();
    if (!startsAt.isAfter(now)) {
      throw const AppException('Pick a time in the future.');
    }
    if (startsAt.isAfter(now.add(bookAhead))) {
      throw const AppException('Bookings open 30 days ahead.');
    }
    final db = await _db.database;
    final id = _uuid.v4();
    await db.transaction((txn) async {
      final ends = startsAt.add(Duration(minutes: durationMinutes));
      await _checkFree(
        txn,
        startsAt: startsAt,
        endsAt: ends,
        barberId: barberId,
        clientId: client.id,
      );
      await txn.insert('bookings', {
        'id': id,
        'shop_id': shopId,
        'client_id': client.id,
        'barber_id': barberId,
        'service_name': serviceName,
        'duration_minutes': durationMinutes,
        'starts_at': startsAt.toIso8601String(),
        'status': BookingStatus.pending.name,
        'created_at': now.toIso8601String(),
      });
    });
    return (await _bookings('k.id = ?', [id])).single;
  }

  /// No double booking: a barber (when one is chosen) and a client each
  /// have at most one active booking at any moment.
  Future<void> _checkFree(
    DatabaseExecutor txn, {
    required DateTime startsAt,
    required DateTime endsAt,
    required String? barberId,
    required String clientId,
    String? exceptId,
  }) async {
    // Overlap: existing.start < new.end AND existing.end > new.start.
    final rows = await txn.query(
      'bookings',
      columns: ['barber_id', 'client_id', 'starts_at', 'duration_minutes'],
      where:
          "status IN ('pending', 'accepted') AND id != ? AND "
          '(client_id = ? OR (barber_id IS NOT NULL AND barber_id = ?)) AND '
          'starts_at < ?',
      whereArgs: [
        exceptId ?? '',
        clientId,
        barberId ?? '',
        endsAt.toIso8601String(),
      ],
    );
    for (final r in rows) {
      final start = DateTime.parse(r['starts_at'] as String);
      final end = start.add(Duration(minutes: r['duration_minutes'] as int));
      if (!end.isAfter(startsAt)) continue;
      if (r['client_id'] == clientId) {
        throw const AppException('You already have a booking at that time.');
      }
      throw const AppException(
        'This barber is already booked at that time. Pick another time.',
      );
    }
  }

  Future<List<Booking>> _bookings(String where, List<Object?> args) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '$_bookingSelect WHERE $where ORDER BY k.starts_at ASC',
      args,
    );
    return rows.map(_booking).toList();
  }

  Future<List<Booking>> myBookings(String clientId) =>
      _bookings('k.client_id = ?', [clientId]);

  /// The salon's bookings from today on.
  Future<List<Booking>> shopBookings(String shopId) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return _bookings('k.shop_id = ? AND k.starts_at >= ?', [
      shopId,
      start.toIso8601String(),
    ]);
  }

  /// A barber's bookings from today on, plus the salon's bookings that let
  /// the salon choose the barber.
  Future<List<Booking>> barberBookings(String shopId, String barberId) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return _bookings(
      'k.shop_id = ? AND (k.barber_id = ? OR k.barber_id IS NULL) '
      'AND k.starts_at >= ?',
      [shopId, barberId, start.toIso8601String()],
    );
  }

  Future<void> cancelBooking(String bookingId, String clientId) async {
    final db = await _db.database;
    final n = await db.update(
      'bookings',
      {'status': BookingStatus.cancelled.name},
      where: "id = ? AND client_id = ? AND status IN ('pending', 'accepted')",
      whereArgs: [bookingId, clientId],
    );
    if (n == 0) throw const AppException('This booking can no longer change.');
  }

  /// The salon accepts or declines a pending booking.
  Future<void> answerBooking(String bookingId, {required bool accept}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'bookings',
        where: 'id = ?',
        whereArgs: [bookingId],
      );
      if (rows.isEmpty || rows.first['status'] != 'pending') {
        throw const AppException('This booking was already answered.');
      }
      await txn.update(
        'bookings',
        {
          'status': accept
              ? BookingStatus.accepted.name
              : BookingStatus.declined.name,
        },
        where: 'id = ?',
        whereArgs: [bookingId],
      );
    });
  }

  /// The client arrived: the booking is done and they join the line, so
  /// their visit is linked to their account.
  Future<void> checkIn(String bookingId) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('$_bookingSelect WHERE k.id = ?', [
        bookingId,
      ]);
      if (rows.isEmpty || rows.first['status'] != 'accepted') {
        throw const AppException('Only confirmed bookings can check in.');
      }
      final b = _booking(rows.first);
      await txn.update(
        'bookings',
        {'status': BookingStatus.done.name},
        where: 'id = ?',
        whereArgs: [bookingId],
      );
      await txn.delete(
        'queue',
        where: "client_id = ? AND status = 'waiting'",
        whereArgs: [b.clientId],
      );
      await txn.insert('queue', {
        'id': _uuid.v4(),
        'shop_id': b.shopId,
        'client_name': b.clientName,
        'client_id': b.clientId,
        'requested_barber_id': b.barberId,
        'notes': 'Booked: ${b.serviceName}',
        'status': 'waiting',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Visits and ratings
  // ---------------------------------------------------------------------------

  Future<List<Visit>> myVisits(String clientId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT t.id, t.shop_id, t.barber_id, t.service_names, t.total_price,
        t.timestamp, s.name AS shop_name, b.name AS barber_name, v.stars
      FROM tickets t
      JOIN shops s ON s.id = t.shop_id
      JOIN barbers b ON b.id = t.barber_id
      LEFT JOIN visit_ratings v ON v.ticket_id = t.id
      WHERE t.client_id = ?
      ORDER BY t.timestamp DESC
    ''',
      [clientId],
    );
    return [
      for (final r in rows)
        Visit(
          ticketId: r['id'] as String,
          shopId: r['shop_id'] as String,
          shopName: r['shop_name'] as String,
          barberId: r['barber_id'] as String,
          barberName: r['barber_name'] as String,
          services: r['service_names'] as String,
          total: (r['total_price'] as num).toDouble(),
          time: DateTime.parse(r['timestamp'] as String),
          stars: r['stars'] as int?,
        ),
    ];
  }

  /// Rates a visit of this client; this is what the barber's rating is
  /// made of. Rating again replaces the stars.
  Future<void> rateVisit({
    required String clientId,
    required String ticketId,
    required int stars,
  }) async {
    _checkStars(stars);
    final db = await _db.database;
    final ticket = await db.query(
      'tickets',
      columns: ['barber_id'],
      where: 'id = ? AND client_id = ?',
      whereArgs: [ticketId, clientId],
    );
    if (ticket.isEmpty) {
      throw const AppException('You can only rate your own visits.');
    }
    await db.insert('visit_ratings', {
      'ticket_id': ticketId,
      'barber_id': ticket.first['barber_id'],
      'client_id': clientId,
      'stars': stars,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// A photo's stars; separate from the barber's visit rating.
  Future<void> ratePhoto({
    required String clientId,
    required String postId,
    required int stars,
  }) async {
    _checkStars(stars);
    final db = await _db.database;
    await db.insert('photo_ratings', {
      'post_id': postId,
      'client_id': clientId,
      'stars': stars,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> myPhotoRating(String clientId, String postId) async {
    final db = await _db.database;
    final rows = await db.query(
      'photo_ratings',
      columns: ['stars'],
      where: 'post_id = ? AND client_id = ?',
      whereArgs: [postId, clientId],
    );
    return rows.isEmpty ? null : rows.first['stars'] as int;
  }

  Future<void> comment({
    required AppUser author,
    required String postId,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) throw const AppException('Write a comment first.');
    if (text.length > 500) {
      throw const AppException('Comments are limited to 500 characters.');
    }
    final db = await _db.database;
    await db.insert('post_comments', {
      'id': _uuid.v4(),
      'post_id': postId,
      'author_id': author.id,
      'author_name': author.fullName,
      'body': text,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static void _checkStars(int stars) {
    if (stars < 1 || stars > 5) {
      throw const AppException('Give between 1 and 5 stars.');
    }
  }
}

final clientActivityProvider = Provider<ClientActivityRepository>(
  (ref) => ClientActivityRepository(ref.watch(databaseServiceProvider)),
);

/// The signed-in client's id, or null for a guest.
final _clientIdProvider = Provider<String?>(
  (ref) => ref.watch(clientSessionProvider.select((s) => s.user?.id)),
);

final favoriteSalonsProvider = FutureProvider.autoDispose<List<ClientSalon>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final id = ref.watch(_clientIdProvider);
  if (id == null) return const [];
  return ref.read(clientActivityProvider).favorites(id);
});

final myQueueSpotProvider = FutureProvider.autoDispose<QueueSpot?>((ref) {
  ref.watch(dataRevisionProvider);
  final id = ref.watch(_clientIdProvider);
  if (id == null) return Future.value();
  return ref.read(clientActivityProvider).mySpot(id);
});

final myBookingsProvider = FutureProvider.autoDispose<List<Booking>>((ref) {
  ref.watch(dataRevisionProvider);
  final id = ref.watch(_clientIdProvider);
  if (id == null) return Future.value(const []);
  return ref.read(clientActivityProvider).myBookings(id);
});

final myVisitsProvider = FutureProvider.autoDispose<List<Visit>>((ref) {
  ref.watch(dataRevisionProvider);
  final id = ref.watch(_clientIdProvider);
  if (id == null) return Future.value(const []);
  return ref.read(clientActivityProvider).myVisits(id);
});

final myPhotoRatingProvider = FutureProvider.autoDispose.family<int?, String>((
  ref,
  postId,
) {
  final id = ref.watch(_clientIdProvider);
  if (id == null) return Future.value();
  return ref.read(clientActivityProvider).myPhotoRating(id, postId);
});
