import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/auth/account_auth.dart';
import '../../core/database/database_service.dart';
import '../../core/errors/app_exception.dart';
import '../../core/providers/core_providers.dart';
import '../barbers/data/barber_invites.dart';

/// A barber account's place in a salon: the roster entry it is linked to.
class BarberLink {
  const BarberLink({
    required this.barberId,
    required this.barberName,
    required this.shopId,
    required this.shopName,
    required this.commissionRate,
    required this.isOnDuty,
    this.assignedChair,
    this.requestedName,
  });

  final String barberId;
  final String barberName;
  final String shopId;
  final String shopName;
  final double commissionRate;
  final bool isOnDuty;
  final int? assignedChair;

  /// A new name the barber asked for, waiting for the owner.
  final String? requestedName;
}

/// What an invitation code opens, shown before the barber signs up.
class InvitePreview {
  const InvitePreview({
    required this.code,
    required this.shopName,
    required this.barberName,
  });

  final String code;
  final String shopName;

  /// The name the owner registered; it becomes the account's name.
  final String barberName;
}

/// Barber accounts and their salon. Failures are thrown as [AppException].
abstract class BarberLinkRepository {
  /// The salon this account is linked to, or null before joining one.
  Future<BarberLink?> myLink(String userId);

  /// Links this account with an invitation code from the salon owner.
  Future<BarberLink> join(String userId, String code);

  /// What [code] opens, or null if it is not valid. Needs no account.
  Future<InvitePreview?> preview(String code);

  /// Asks the owner to change this barber's name.
  Future<void> requestNameChange(String name);

  /// Unlinks this account from its salon. The account stays.
  Future<void> leave();
}

/// [BarberLinkRepository] on this device's database.
class LocalBarberLinkRepository implements BarberLinkRepository {
  LocalBarberLinkRepository(this._db, this._auth);

  final DatabaseService _db;
  final AccountAuth _auth;

  @override
  Future<BarberLink?> myLink(String userId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT b.*, s.name AS shop_name
      FROM barbers b JOIN shops s ON s.id = b.shop_id
      WHERE b.profile_id = ? AND b.is_archived = 0
      LIMIT 1
    ''',
      [userId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return BarberLink(
      barberId: r['id'] as String,
      barberName: r['name'] as String,
      shopId: r['shop_id'] as String,
      shopName: r['shop_name'] as String,
      commissionRate: (r['commission_rate'] as num).toDouble(),
      isOnDuty: r['is_on_duty'] == 1,
      assignedChair: r['assigned_chair'] as int?,
      requestedName: r['requested_name'] as String?,
    );
  }

  @override
  Future<BarberLink> join(String userId, String code) async {
    final cleaned = _checkedCode(code);
    final db = await _db.database;
    await db.transaction((txn) async {
      final linked = await txn.query(
        'barbers',
        columns: ['id'],
        where: 'profile_id = ? AND is_archived = 0',
        whereArgs: [userId],
      );
      if (linked.isNotEmpty) {
        throw const AppException(
          'You already belong to a salon. Leave it first.',
        );
      }
      final invite = await _openInvite(txn, cleaned);
      if (invite == null) throw const AppException(_invalidCode);
      await txn.update(
        'barbers',
        {'profile_id': userId},
        where: 'id = ?',
        whereArgs: [invite['barber_id']],
      );
      await txn.update(
        'barber_invites',
        {'used_at': DateTime.now().toIso8601String()},
        where: 'code = ?',
        whereArgs: [cleaned],
      );
    });
    final link = await myLink(userId);
    if (link == null) {
      throw const AppException('Could not join the salon. Please try again.');
    }
    return link;
  }

  @override
  Future<InvitePreview?> preview(String code) async {
    final cleaned = _checkedCode(code);
    final db = await _db.database;
    final row = await _openInvite(db, cleaned);
    if (row == null) return null;
    return InvitePreview(
      code: cleaned,
      shopName: row['shop_name'] as String,
      barberName: row['barber_name'] as String,
    );
  }

  @override
  Future<void> requestNameChange(String name) async {
    final wanted = name.trim();
    if (wanted.isEmpty) throw const AppException('Please enter a name.');
    final db = await _db.database;
    await db.update(
      'barbers',
      {'requested_name': wanted},
      where: 'profile_id = ? AND is_archived = 0',
      whereArgs: [_userId],
    );
  }

  @override
  Future<void> leave() async {
    final userId = _userId;
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'barbers',
        columns: ['id'],
        where: 'profile_id = ? AND is_archived = 0',
        whereArgs: [userId],
      );
      if (rows.isEmpty) return;
      final barberId = rows.first['id'] as String;
      final serving = await txn.query(
        'chairs',
        columns: ['chair_number'],
        where: "active_barber_id = ? AND status = 'occupied'",
        whereArgs: [barberId],
      );
      if (serving.isNotEmpty) {
        throw const AppException(
          'You are serving a client. Finish the service before leaving.',
        );
      }
      await txn.update(
        'chairs',
        {'status': 'empty', 'active_barber_id': null},
        where: 'active_barber_id = ?',
        whereArgs: [barberId],
      );
      // The salon keeps the roster entry and its history.
      await txn.update(
        'barbers',
        {
          'profile_id': null,
          'requested_name': null,
          'is_on_duty': 0,
          'assigned_chair': null,
        },
        where: 'id = ?',
        whereArgs: [barberId],
      );
    });
  }

  String get _userId {
    final user = _auth.currentUser;
    if (user == null) throw const AppException('Please sign in again.');
    return user.id;
  }

  static const _invalidCode =
      'This code is not valid or has expired. Ask your salon for a new one.';

  static String _checkedCode(String code) {
    final cleaned = normalizeCode(code);
    if (cleaned.length != 8) {
      throw const AppException('The code has 8 characters.');
    }
    return cleaned;
  }

  /// The unused, unexpired invite [code] for a barber without an account.
  static Future<Map<String, Object?>?> _openInvite(
    DatabaseExecutor db,
    String code,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT i.barber_id, b.name AS barber_name, s.name AS shop_name
      FROM barber_invites i
      JOIN barbers b ON b.id = i.barber_id
      JOIN shops s ON s.id = b.shop_id
      WHERE i.code = ? AND i.used_at IS NULL AND i.expires_at > ?
        AND b.is_archived = 0 AND b.profile_id IS NULL
    ''',
      [code, DateTime.now().toIso8601String()],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Upper case, without spaces or dashes.
  static String normalizeCode(String code) => BarberInvites.normalizeCode(code);
}

final barberLinkRepositoryProvider = Provider<BarberLinkRepository>((ref) {
  return LocalBarberLinkRepository(
    ref.watch(databaseServiceProvider),
    ref.watch(accountAuthProvider),
  );
});
