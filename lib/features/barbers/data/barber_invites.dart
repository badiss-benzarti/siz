import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_service.dart';
import '../../../core/providers/core_providers.dart';

/// A code the owner gives one barber so they can create their account.
class BarberInvite {
  const BarberInvite(this.code, this.expiresAt);

  final String code;
  final DateTime expiresAt;
}

/// Invitation codes for barbers: 8 characters, single use, valid 7 days.
class BarberInvites {
  BarberInvites(this._db, {Random? random})
    : _random = random ?? Random.secure();

  final DatabaseService _db;
  final Random _random;

  static const validFor = Duration(days: 7);

  /// No 0/O or 1/I/L, so a code read aloud is not misheard.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// A new code for [barberId], replacing any unused previous one.
  Future<BarberInvite> create(String barberId) async {
    final db = await _db.database;
    final invite = BarberInvite(
      List.generate(
        8,
        (_) => _alphabet[_random.nextInt(_alphabet.length)],
      ).join(),
      DateTime.now().add(validFor),
    );
    await db.transaction((txn) async {
      await txn.delete(
        'barber_invites',
        where: 'barber_id = ? AND used_at IS NULL',
        whereArgs: [barberId],
      );
      await txn.insert('barber_invites', {
        'code': invite.code,
        'barber_id': barberId,
        'expires_at': invite.expiresAt.toIso8601String(),
      });
    });
    return invite;
  }

  /// Upper case, without spaces or dashes.
  static String normalizeCode(String code) =>
      code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
}

final barberInvitesProvider = Provider<BarberInvites>(
  (ref) => BarberInvites(ref.watch(databaseServiceProvider)),
);
