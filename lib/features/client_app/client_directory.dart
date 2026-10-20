import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_service.dart';
import '../../core/errors/app_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../core/providers/data_revision.dart';
import '../../core/repositories/floor_plan_repository.dart';
import '../barber_app/portfolio.dart' show PostQuery;
import '../floor_plan/domain/station.dart';

/// A salon as clients see it in the list of salons.
class ClientSalon {
  const ClientSalon({
    required this.id,
    required this.name,
    required this.address,
    required this.isOpen,
    required this.waitingCount,
    required this.totalChairs,
    required this.established,
  });

  final String id;
  final String name;
  final String address;
  final bool isOpen;
  final int waitingCount;
  final int totalChairs;
  final int established;

  SalonLoad get load => !isOpen
      ? SalonLoad.closed
      : waitingCount >= busyFrom
      ? SalonLoad.busy
      : SalonLoad.available;

  /// From this many clients waiting, a salon shows as busy.
  static const busyFrom = 4;
}

enum SalonLoad { available, busy, closed }

class ClientBarber {
  const ClientBarber({
    required this.id,
    required this.name,
    required this.specialty,
    required this.isOnDuty,
    required this.ratingAvg,
    required this.ratingCount,
  });

  final String id;
  final String name;
  final String specialty;
  final bool isOnDuty;

  /// From clients' ratings of real visits.
  final double ratingAvg;
  final int ratingCount;
}

class ClientService {
  const ClientService(this.name, this.price, this.minutes);

  final String name;
  final double price;
  final int minutes;
}

/// A photo of a cut, as shown on the salon page and in Social.
class ClientPost {
  const ClientPost({
    required this.id,
    required this.shopId,
    required this.barberName,
    required this.imageUrl,
    required this.caption,
    required this.ratingAvg,
    required this.ratingCount,
    required this.commentCount,
    required this.createdAt,
    this.shopName,
  });

  final String id;
  final String shopId;
  final String? shopName;
  final String barberName;
  final String imageUrl;
  final String caption;
  final double ratingAvg;
  final int ratingCount;
  final int commentCount;
  final DateTime createdAt;
}

class ClientComment {
  const ClientComment(this.authorName, this.body, this.createdAt);

  final String authorName;
  final String body;
  final DateTime createdAt;
}

/// Everything on a salon's page.
class SalonDetails {
  const SalonDetails({
    required this.salon,
    required this.barbers,
    required this.services,
    required this.stations,
    required this.posts,
  });

  final ClientSalon salon;
  final List<ClientBarber> barbers;
  final List<ClientService> services;

  /// Chairs with their barber; never who is seated.
  final List<Station> stations;
  final List<ClientPost> posts;

  int get barbersOnDuty => barbers.where((b) => b.isOnDuty).length;
}

/// What clients can see: listed salons only, and only their public side
/// (never who sits in a chair). Works without an account. Failures are
/// thrown as `AppException`.
abstract class ClientDirectory {
  /// Every salon shown to clients.
  Future<List<ClientSalon>> salons();

  Future<SalonDetails> salon(String shopId);

  /// Latest photos from all listed salons.
  Future<List<ClientPost>> latestPosts({int limit = 30});

  Future<List<ClientComment>> comments(String postId);
}

/// SQL for salons as clients see them.
abstract final class SalonQuery {
  static const select = '''
    SELECT s.id, s.name, s.address, s.is_open, s.total_chairs, s.created_at,
      (SELECT COUNT(*) FROM queue q
        WHERE q.shop_id = s.id AND q.status = 'waiting') AS waiting_count
    FROM shops s
  ''';

  static ClientSalon read(Map<String, Object?> r) => ClientSalon(
    id: r['id'] as String,
    name: r['name'] as String,
    address: r['address'] as String,
    isOpen: r['is_open'] == 1,
    waitingCount: r['waiting_count'] as int,
    totalChairs: r['total_chairs'] as int,
    established: DateTime.parse(r['created_at'] as String).year,
  );

  static ClientPost readPost(Map<String, Object?> p) => ClientPost(
    id: p['id'] as String,
    shopId: p['shop_id'] as String,
    shopName: p['shop_name'] as String?,
    barberName: p['barber_name'] as String,
    imageUrl: p['image'] as String,
    caption: p['caption'] as String,
    ratingAvg: (p['rating_avg'] as num?)?.toDouble() ?? 0,
    ratingCount: p['rating_count'] as int,
    commentCount: p['comment_count'] as int,
    createdAt: DateTime.parse(p['created_at'] as String),
  );
}

/// [ClientDirectory] on this device's database.
class LocalClientDirectory implements ClientDirectory {
  LocalClientDirectory(this._db);

  final DatabaseService _db;

  @override
  Future<List<ClientSalon>> salons() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '${SalonQuery.select} WHERE s.is_listed = 1 ORDER BY s.name',
    );
    return rows.map(SalonQuery.read).toList();
  }

  @override
  Future<SalonDetails> salon(String shopId) async {
    final db = await _db.database;
    final shop = await db.rawQuery('${SalonQuery.select} WHERE s.id = ?', [
      shopId,
    ]);
    if (shop.isEmpty) throw const AppException('This salon is not available.');
    final salon = SalonQuery.read(shop.first);

    final barbers = await db.rawQuery(
      '''
      SELECT b.id, b.name, b.specialty, b.is_on_duty,
        (SELECT AVG(stars) FROM visit_ratings v WHERE v.barber_id = b.id)
          AS rating_avg,
        (SELECT COUNT(*) FROM visit_ratings v WHERE v.barber_id = b.id)
          AS rating_count
      FROM barbers b
      WHERE b.shop_id = ? AND b.is_archived = 0
      ORDER BY b.name
    ''',
      [shopId],
    );
    final services = await db.query(
      'services',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'price ASC',
    );
    final stations = await FloorPlanRepository(dbService: _db)
        .getStations(shopId);
    final posts = await db.rawQuery(
      '${PostQuery.select} WHERE p.shop_id = ? '
      'ORDER BY p.created_at DESC LIMIT 60',
      [shopId],
    );

    return SalonDetails(
      salon: salon,
      barbers: [
        for (final b in barbers)
          ClientBarber(
            id: b['id'] as String,
            name: b['name'] as String,
            specialty: b['specialty'] as String,
            isOnDuty: b['is_on_duty'] == 1,
            ratingAvg: (b['rating_avg'] as num?)?.toDouble() ?? 0,
            ratingCount: b['rating_count'] as int,
          ),
      ],
      services: [
        for (final r in services)
          ClientService(
            r['name'] as String,
            (r['price'] as num).toDouble(),
            r['duration_minutes'] as int,
          ),
      ],
      // The chair and its barber only: clients never see who is seated.
      stations: [
        for (final c in stations)
          Station(
            chairNumber: c.chairNumber,
            shopId: shopId,
            status: c.status,
            activeBarberId: c.activeBarberId,
            activeBarberName: c.activeBarberName,
            serviceStartTime: c.serviceStartTime,
          ),
      ],
      posts: posts.map(SalonQuery.readPost).toList(),
    );
  }

  @override
  Future<List<ClientPost>> latestPosts({int limit = 30}) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '${PostQuery.select} WHERE s.is_listed = 1 '
      'ORDER BY p.created_at DESC LIMIT ?',
      [limit],
    );
    return rows.map(SalonQuery.readPost).toList();
  }

  @override
  Future<List<ClientComment>> comments(String postId) async {
    final db = await _db.database;
    final rows = await db.query(
      'post_comments',
      where: 'post_id = ?',
      whereArgs: [postId],
      orderBy: 'created_at ASC',
    );
    return [
      for (final r in rows)
        ClientComment(
          r['author_name'] as String,
          r['body'] as String,
          DateTime.parse(r['created_at'] as String),
        ),
    ];
  }
}

final clientDirectoryProvider = Provider<ClientDirectory>(
  (ref) => LocalClientDirectory(ref.watch(databaseServiceProvider)),
);

/// Every salon shown to clients.
final salonListProvider = FutureProvider.autoDispose<List<ClientSalon>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.read(clientDirectoryProvider).salons();
});

/// A salon's page, refreshed when reopened or pulled down.
final salonDetailsProvider = FutureProvider.autoDispose
    .family<SalonDetails, String>((ref, shopId) {
      ref.watch(dataRevisionProvider);
      return ref.read(clientDirectoryProvider).salon(shopId);
    });

final latestPostsProvider = FutureProvider.autoDispose<List<ClientPost>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.read(clientDirectoryProvider).latestPosts();
});

final clientCommentsProvider = FutureProvider.autoDispose
    .family<List<ClientComment>, String>((ref, postId) {
      ref.watch(dataRevisionProvider);
      return ref.read(clientDirectoryProvider).comments(postId);
    });
