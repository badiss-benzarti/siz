import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../errors/app_exception.dart';
import '../../features/barbers/domain/barber.dart';

class BarberRepository {
  BarberRepository({required this._dbService});

  final DatabaseService _dbService;
  final _uuid = const Uuid();

  static const double minCommission = 0.0;
  static const double maxCommission = 1.0;

  /// Active (non-archived) barbers of a shop.
  Future<List<Barber>> getBarbers(String shopId) async {
    final db = await _dbService.database;
    final results = await db.query(
      'barbers',
      where: 'shop_id = ? AND is_archived = 0',
      whereArgs: [shopId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return results.map(Barber.fromMap).toList();
  }

  Future<Barber> addBarber({
    required String shopId,
    required String name,
    required String phone,
    required double commissionRate,
  }) async {
    _validate(name, commissionRate);
    final db = await _dbService.database;
    final barber = Barber(
      id: _uuid.v4(),
      shopId: shopId,
      name: name.trim(),
      phone: phone.trim(),
      commissionRate: commissionRate,
      isOnDuty: true,
      createdAt: DateTime.now(),
    );

    await db.insert('barbers', barber.toMap());
    return barber;
  }

  Future<void> updateBarber({
    required String barberId,
    required String name,
    required String phone,
    required double commissionRate,
  }) async {
    _validate(name, commissionRate);
    final db = await _dbService.database;
    await db.update(
      'barbers',
      {
        'name': name.trim(),
        'phone': phone.trim(),
        'commission_rate': commissionRate,
      },
      where: 'id = ?',
      whereArgs: [barberId],
    );
  }

  /// Going off duty frees the barber's chair. Refused mid-service.
  Future<void> setOnDuty(String barberId, bool isOnDuty) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      if (!isOnDuty) {
        await _releaseChair(txn, barberId);
      }
      await txn.update(
        'barbers',
        {'is_on_duty': isOnDuty ? 1 : 0},
        where: 'id = ?',
        whereArgs: [barberId],
      );
    });
  }

  /// Applies the owner's answer to a barber's name request.
  Future<void> applyNameAnswer(String barberId, {String? acceptedName}) async {
    final db = await _dbService.database;
    await db.update(
      'barbers',
      {'requested_name': null, 'name': ?acceptedName},
      where: 'id = ?',
      whereArgs: [barberId],
    );
  }

  /// Removes a barber from the roster while keeping their financial history.
  Future<void> archiveBarber(String barberId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await _releaseChair(txn, barberId);
      await txn.update(
        'barbers',
        {'is_archived': 1, 'is_on_duty': 0, 'assigned_chair': null},
        where: 'id = ?',
        whereArgs: [barberId],
      );
      await txn.update(
        'queue',
        {'requested_barber_id': null},
        where: 'requested_barber_id = ?',
        whereArgs: [barberId],
      );
    });
  }

  Future<void> _releaseChair(Transaction txn, String barberId) async {
    final chairs = await txn.query(
      'chairs',
      where: 'active_barber_id = ?',
      whereArgs: [barberId],
    );
    for (final chair in chairs) {
      if (chair['status'] == 'occupied') {
        throw AppException(
          'This barber is serving a client at chair #${chair['chair_number']}. '
          'Check out the client first.',
        );
      }
    }
    await txn.update(
      'chairs',
      {
        'status': 'empty',
        'active_barber_id': null,
        'active_client_name': null,
        'active_client_id': null,
        'active_ticket_id': null,
        'service_start_time': null,
      },
      where: 'active_barber_id = ?',
      whereArgs: [barberId],
    );
    await txn.update(
      'barbers',
      {'assigned_chair': null},
      where: 'id = ?',
      whereArgs: [barberId],
    );
  }

  void _validate(String name, double commissionRate) {
    if (name.trim().isEmpty) {
      throw const AppException('Barber name is required.');
    }
    if (commissionRate.isNaN ||
        commissionRate < minCommission ||
        commissionRate > maxCommission) {
      throw const AppException('Commission must be between 0% and 100%.');
    }
  }
}
