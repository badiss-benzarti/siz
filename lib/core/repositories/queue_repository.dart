import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../errors/app_exception.dart';
import '../../features/queue/domain/queue_item.dart';

class QueueRepository {
  QueueRepository({required this._dbService});

  final DatabaseService _dbService;
  final _uuid = const Uuid();

  Future<List<QueueItem>> getWaitingQueue(String shopId) async {
    final db = await _dbService.database;
    final results = await db.query(
      'queue',
      where: 'shop_id = ? AND status = ?',
      whereArgs: [shopId, 'waiting'],
      orderBy: 'created_at ASC',
    );
    return results.map(QueueItem.fromMap).toList();
  }

  Future<QueueItem> addToQueue({
    required String shopId,
    required String clientName,
    String? clientPhone,
    String? requestedBarberId,
    String? notes,
    String? clientId,
  }) async {
    if (clientName.trim().isEmpty) {
      throw const AppException('Client name is required.');
    }
    final db = await _dbService.database;
    final item = QueueItem(
      id: _uuid.v4(),
      shopId: shopId,
      clientName: clientName.trim(),
      clientPhone: _blankToNull(clientPhone),
      requestedBarberId: requestedBarberId,
      notes: _blankToNull(notes),
      status: 'waiting',
      createdAt: DateTime.now(),
    );

    await db.insert('queue', {...item.toMap(), 'client_id': clientId});
    return item;
  }

  Future<void> markAsSeated(String id) async {
    final db = await _dbService.database;
    await db.update(
      'queue',
      {'status': 'seated'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> removeFromQueue(String id) async {
    final db = await _dbService.database;
    await db.delete('queue', where: 'id = ?', whereArgs: [id]);
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
