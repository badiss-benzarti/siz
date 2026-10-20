import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_auth.dart';
import '../../core/database/database_service.dart';
import '../../core/errors/app_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../core/repositories/barber_repository.dart';
import '../../core/repositories/floor_plan_repository.dart';
import '../../core/repositories/queue_repository.dart';
import '../floor_plan/domain/station.dart';
import '../queue/domain/queue_item.dart';
import 'barber_session.dart';

/// The barber's salon right now: its floor and who is waiting.
class SalonFloor {
  const SalonFloor({
    required this.shopName,
    required this.established,
    required this.totalChairs,
    required this.isOpen,
    required this.stations,
    required this.queue,
  });

  final String shopName;
  final int established;
  final int totalChairs;
  final bool isOpen;
  final List<Station> stations;

  /// Clients waiting, first arrived first.
  final List<QueueItem> queue;
}

/// Reads the barber's salon and changes what a barber may.
/// Failures are thrown as `AppException`.
abstract class BarberSalonRepository {
  Future<SalonFloor> load(String shopId);

  /// On or off duty. Going off duty frees the barber's chair, and is refused
  /// while serving a client.
  Future<void> setMyDuty({required bool onDuty});

  Future<void> addWalkIn(String shopId, String clientName);
}

/// [BarberSalonRepository] on this device's database.
class LocalBarberSalonRepository implements BarberSalonRepository {
  LocalBarberSalonRepository(this._db, this._auth);

  final DatabaseService _db;
  final AccountAuth _auth;

  FloorPlanRepository get _floor => FloorPlanRepository(dbService: _db);
  QueueRepository get _queue => QueueRepository(dbService: _db);

  @override
  Future<SalonFloor> load(String shopId) async {
    final db = await _db.database;
    final shops = await db.query('shops', where: 'id = ?', whereArgs: [shopId]);
    if (shops.isEmpty) throw const AppException('This salon no longer exists.');
    final shop = shops.first;
    return SalonFloor(
      shopName: shop['name'] as String,
      established: DateTime.parse(shop['created_at'] as String).year,
      totalChairs: shop['total_chairs'] as int,
      isOpen: shop['is_open'] == 1,
      stations: await _floor.getStations(shopId),
      queue: await _queue.getWaitingQueue(shopId),
    );
  }

  @override
  Future<void> setMyDuty({required bool onDuty}) async {
    final user = _auth.currentUser;
    if (user == null) throw const AppException('Please sign in again.');
    final db = await _db.database;
    final rows = await db.query(
      'barbers',
      columns: ['id'],
      where: 'profile_id = ? AND is_archived = 0',
      whereArgs: [user.id],
    );
    if (rows.isEmpty) throw const AppException('You are not in a salon.');
    await BarberRepository(dbService: _db)
        .setOnDuty(rows.first['id'] as String, onDuty);
  }

  @override
  Future<void> addWalkIn(String shopId, String clientName) async {
    await _queue.addToQueue(shopId: shopId, clientName: clientName);
  }
}

final barberSalonRepositoryProvider = Provider<BarberSalonRepository>((ref) {
  return LocalBarberSalonRepository(
    ref.watch(databaseServiceProvider),
    ref.watch(accountAuthProvider),
  );
});

/// The linked salon's floor, refreshed every 30 seconds while shown.
final barberFloorProvider =
    AsyncNotifierProvider.autoDispose<BarberFloorNotifier, SalonFloor>(
      BarberFloorNotifier.new,
    );

class BarberFloorNotifier extends AsyncNotifier<SalonFloor> {
  static const refreshEvery = Duration(seconds: 30);

  BarberSalonRepository get _repo => ref.read(barberSalonRepositoryProvider);

  String? get _shopId => ref.read(barberSessionProvider).link?.shopId;

  @override
  Future<SalonFloor> build() async {
    final shopId = ref.watch(
      barberSessionProvider.select((s) => s.link?.shopId),
    );
    if (shopId == null) throw StateError('Not linked to a salon.');
    final timer = Timer.periodic(refreshEvery, (_) => _quietRefresh());
    ref.onDispose(timer.cancel);
    return _repo.load(shopId);
  }

  /// Background refresh: keeps the last floor if a read fails.
  Future<void> _quietRefresh() async {
    final shopId = _shopId;
    if (shopId == null) return;
    try {
      final floor = await _repo.load(shopId);
      if (ref.mounted) state = AsyncData(floor);
    } catch (_) {}
  }

  /// Pull-to-refresh; throws so the screen can say what went wrong.
  Future<void> refresh() async {
    final shopId = _shopId;
    if (shopId == null) return;
    final floor = await _repo.load(shopId);
    if (ref.mounted) state = AsyncData(floor);
  }

  Future<void> setDuty({required bool onDuty}) async {
    await _repo.setMyDuty(onDuty: onDuty);
    await ref.read(barberSessionProvider.notifier).refresh();
    await _quietRefresh();
  }

  Future<void> addWalkIn(String clientName) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await _repo.addWalkIn(shopId, clientName);
    await _quietRefresh();
  }
}
