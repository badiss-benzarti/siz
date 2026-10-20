import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../errors/app_exception.dart';
import '../../features/auth_onboarding/domain/shop_profile.dart';
import '../../features/finance/domain/service_ticket.dart';
import '../../features/floor_plan/domain/station.dart';

class FloorPlanRepository {
  FloorPlanRepository({required this._dbService});

  final DatabaseService _dbService;
  final _uuid = const Uuid();

  static const Map<String, Object?> _clearedClient = {
    'active_client_name': null,
    'active_client_id': null,
    'active_ticket_id': null,
    'service_start_time': null,
  };

  /// All stations of a shop with their assigned barber names.
  Future<List<Station>> getStations(String shopId) async {
    final db = await _dbService.database;
    final results = await db.rawQuery(
      '''
      SELECT c.*, b.name AS barber_name
      FROM chairs c
      LEFT JOIN barbers b ON c.active_barber_id = b.id
      WHERE c.shop_id = ?
      ORDER BY c.chair_number ASC
    ''',
      [shopId],
    );

    return results
        .map(
          (row) =>
              Station.fromMap(row, barberName: row['barber_name'] as String?),
        )
        .toList();
  }

  /// Puts an on-duty barber at a chair, moving them from any previous chair.
  Future<void> assignBarberToChair({
    required String shopId,
    required int chairNumber,
    required String barberId,
  }) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      final target = await _getChair(txn, shopId, chairNumber);
      if (target['status'] == 'occupied') {
        throw const AppException('This chair is serving a client.');
      }

      final barbers = await txn.query(
        'barbers',
        where: 'id = ? AND shop_id = ? AND is_archived = 0',
        whereArgs: [barberId, shopId],
      );
      if (barbers.isEmpty) {
        throw const AppException('Barber not found.');
      }
      if (barbers.first['is_on_duty'] != 1) {
        throw const AppException('Put this barber on duty first.');
      }

      final previous = await txn.query(
        'chairs',
        where: 'shop_id = ? AND active_barber_id = ?',
        whereArgs: [shopId, barberId],
      );
      if (previous.any((c) => c['status'] == 'occupied')) {
        throw const AppException(
          'This barber is serving a client. Check out the client first.',
        );
      }
      await txn.update(
        'chairs',
        {'status': 'empty', 'active_barber_id': null, ..._clearedClient},
        where: 'shop_id = ? AND active_barber_id = ?',
        whereArgs: [shopId, barberId],
      );

      final displacedBarberId = target['active_barber_id'] as String?;
      if (displacedBarberId != null && displacedBarberId != barberId) {
        await txn.update(
          'barbers',
          {'assigned_chair': null},
          where: 'id = ?',
          whereArgs: [displacedBarberId],
        );
      }

      await txn.update(
        'chairs',
        {
          'status': 'available',
          'active_barber_id': barberId,
          ..._clearedClient,
        },
        where: 'shop_id = ? AND chair_number = ?',
        whereArgs: [shopId, chairNumber],
      );
      await txn.update(
        'barbers',
        {'assigned_chair': chairNumber},
        where: 'id = ?',
        whereArgs: [barberId],
      );
    });
  }

  /// Frees a chair. Refused while a client is being served.
  Future<void> unassignBarber({
    required String shopId,
    required int chairNumber,
  }) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      final chair = await _getChair(txn, shopId, chairNumber);
      if (chair['status'] == 'occupied') {
        throw const AppException(
          'Check out or cancel the current service before vacating the chair.',
        );
      }

      final barberId = chair['active_barber_id'] as String?;
      if (barberId != null) {
        await txn.update(
          'barbers',
          {'assigned_chair': null},
          where: 'id = ?',
          whereArgs: [barberId],
        );
      }

      await txn.update(
        'chairs',
        {'status': 'empty', 'active_barber_id': null, ..._clearedClient},
        where: 'shop_id = ? AND chair_number = ?',
        whereArgs: [shopId, chairNumber],
      );
    });
  }

  /// Starts a service at a staffed chair. When [queueItemId] is given the
  /// client is taken off the waiting list in the same transaction.
  Future<void> seatClient({
    required String shopId,
    required int chairNumber,
    required String clientName,
    String? queueItemId,
  }) async {
    final name = clientName.trim();
    if (name.isEmpty) {
      throw const AppException('Client name is required.');
    }

    final db = await _dbService.database;
    await db.transaction((txn) async {
      final chair = await _getChair(txn, shopId, chairNumber);
      if (chair['status'] != 'available' || chair['active_barber_id'] == null) {
        throw const AppException('This chair is not ready for a client.');
      }

      // A client account waiting in line: its visit is linked to it, so the
      // client can rate it afterwards.
      String? clientId;
      if (queueItemId != null) {
        final waiting = await txn.query(
          'queue',
          columns: ['client_id'],
          where: 'id = ? AND shop_id = ?',
          whereArgs: [queueItemId, shopId],
        );
        if (waiting.isNotEmpty) {
          clientId = waiting.first['client_id'] as String?;
        }
      }

      await txn.update(
        'chairs',
        {
          'status': 'occupied',
          'active_client_name': name,
          'active_client_id': clientId,
          'active_ticket_id': _uuid.v4(),
          'service_start_time': DateTime.now().toIso8601String(),
        },
        where: 'shop_id = ? AND chair_number = ?',
        whereArgs: [shopId, chairNumber],
      );

      if (queueItemId != null) {
        await txn.update(
          'queue',
          {'status': 'seated'},
          where: 'id = ? AND shop_id = ?',
          whereArgs: [queueItemId, shopId],
        );
      }
    });
  }

  /// Ends a service without recording a sale (e.g. seated by mistake).
  Future<void> cancelService({
    required String shopId,
    required int chairNumber,
  }) async {
    final db = await _dbService.database;
    await db.update(
      'chairs',
      {'status': 'available', ..._clearedClient},
      where: 'shop_id = ? AND chair_number = ? AND status = ?',
      whereArgs: [shopId, chairNumber, 'occupied'],
    );
  }

  /// Records the sale and frees the chair in one transaction.
  ///
  /// Prices and the barber's commission are read from the database, never
  /// trusted from the UI. A chair that is no longer occupied (for example a
  /// double tap) is rejected, so a service can only be charged once.
  Future<ServiceTicket> checkoutService({
    required String shopId,
    required int chairNumber,
    required List<String> serviceIds,
    required PaymentMethod paymentMethod,
    double tip = 0.0,
    String? clientPhone,
  }) async {
    if (serviceIds.isEmpty) {
      throw const AppException('Select at least one service.');
    }
    if (tip.isNaN || tip < 0) {
      throw const AppException('Tip cannot be negative.');
    }

    final db = await _dbService.database;
    return db.transaction((txn) async {
      final chair = await _getChair(txn, shopId, chairNumber);
      final barberId = chair['active_barber_id'] as String?;
      if (chair['status'] != 'occupied' || barberId == null) {
        throw const AppException('This service has already been checked out.');
      }

      final barberRows = await txn.query(
        'barbers',
        columns: ['commission_rate'],
        where: 'id = ?',
        whereArgs: [barberId],
      );
      if (barberRows.isEmpty) {
        throw const AppException('Barber not found.');
      }
      final commissionRate = (barberRows.first['commission_rate'] as num)
          .toDouble();

      final placeholders = List.filled(serviceIds.length, '?').join(', ');
      final serviceRows = await txn.query(
        'services',
        where: 'shop_id = ? AND id IN ($placeholders)',
        whereArgs: [shopId, ...serviceIds],
      );
      final byId = {
        for (final row in serviceRows)
          row['id'] as String: ServiceItem.fromMap(row),
      };
      final services = [
        for (final id in serviceIds)
          if (byId[id] != null) byId[id]!,
      ];
      if (services.length != serviceIds.length) {
        throw const AppException(
          'One of the selected services no longer exists.',
        );
      }

      final subtotal = roundMoney(
        services.fold<double>(0, (sum, s) => sum + s.price),
      );
      final barberCut = roundMoney(subtotal * commissionRate);

      final ticket = ServiceTicket(
        id: _uuid.v4(),
        shopId: shopId,
        clientName:
            (chair['active_client_name'] as String?) ?? 'Walk-in Client',
        clientPhone: clientPhone?.trim().isEmpty ?? true
            ? null
            : clientPhone!.trim(),
        barberId: barberId,
        chairNumber: chairNumber,
        serviceNames: services.map((s) => s.name).toList(),
        totalPrice: subtotal,
        barberCut: barberCut,
        shopCut: roundMoney(subtotal - barberCut),
        tip: roundMoney(tip),
        paymentMethod: paymentMethod,
        timestamp: DateTime.now(),
      );

      await txn.insert('tickets', {
        ...ticket.toMap(),
        'client_id': chair['active_client_id'],
      });
      await txn.update(
        'chairs',
        {'status': 'available', ..._clearedClient},
        where: 'shop_id = ? AND chair_number = ?',
        whereArgs: [shopId, chairNumber],
      );
      return ticket;
    });
  }

  static double roundMoney(double value) => (value * 100).roundToDouble() / 100;

  Future<Map<String, Object?>> _getChair(
    Transaction txn,
    String shopId,
    int chairNumber,
  ) async {
    final rows = await txn.query(
      'chairs',
      where: 'shop_id = ? AND chair_number = ?',
      whereArgs: [shopId, chairNumber],
    );
    if (rows.isEmpty) {
      throw AppException('Chair #$chairNumber does not exist.');
    }
    return rows.first;
  }
}
