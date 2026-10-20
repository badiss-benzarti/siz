import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../errors/app_exception.dart';
import '../security/password_hasher.dart';
import '../security/session_storage.dart';

/// What an account is for, chosen at sign-up. It decides which space the
/// app opens, and each space refuses accounts of another role.
enum AccountRole {
  owner,
  barber,
  client;

  static AccountRole parse(Object? value) => switch (value) {
    'owner' => owner,
    'barber' => barber,
    _ => client,
  };
}

/// An account stored on this device.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.role = AccountRole.owner,
  });

  final String id;
  final String email;
  final String fullName;
  final AccountRole role;
}

/// Sign-up, sign-in and the session of accounts. Failures are thrown as
/// [AppException] with a user-facing message.
abstract class AccountAuth {
  /// The account signed in on this device, if any.
  AppUser? get currentUser;

  /// Creates an account and signs it in.
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
    required AccountRole role,
  });

  Future<AppUser> signIn({required String email, required String password});

  Future<void> signOut();
}

/// [AccountAuth] on the device's SQLite database. Every account (owner,
/// barber, client) is a row of `owners` with its role; passwords are stored
/// as salted PBKDF2 hashes, never in clear. One account is signed in at a
/// time, remembered in secure storage.
class LocalAccountAuth implements AccountAuth {
  LocalAccountAuth({
    required this._db,
    required this._hasher,
    required this._session,
  });

  final DatabaseService _db;
  final PasswordHasher _hasher;
  final SessionStorage _session;

  AppUser? _current;

  static const int minPasswordLength = 8;

  @override
  AppUser? get currentUser => _current;

  /// Reads back the account that was signed in when the app was closed.
  /// Called once at start-up, before the first screen.
  Future<void> restore() async {
    final id = await _session.readActiveAccountId();
    if (id == null) return;
    final db = await _db.database;
    final rows = await db.query('owners', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      await _session.clear();
      return;
    }
    _current = _toUser(rows.first);
  }

  @override
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
    required AccountRole role,
  }) async {
    final normalized = normalizeEmail(email);
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const AppException('Enter a valid email address.');
    }
    if (password.length < minPasswordLength) {
      throw const AppException(
        'Password must be at least $minPasswordLength characters.',
      );
    }
    if (fullName.trim().isEmpty) {
      throw const AppException('Please enter your full name.');
    }

    final db = await _db.database;
    final existing = await db.query(
      'owners',
      columns: ['id'],
      where: 'email = ?',
      whereArgs: [normalized],
    );
    if (existing.isNotEmpty) {
      throw const AppException('An account with this email already exists.');
    }

    final salt = _hasher.generateSalt();
    final row = {
      'id': const Uuid().v4(),
      'email': normalized,
      'password_hash': await _hasher.hash(password, salt),
      'salt': salt,
      'full_name': fullName.trim(),
      'role': role.name,
      'created_at': DateTime.now().toIso8601String(),
    };
    await db.insert('owners', row);
    return _start(row);
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'owners',
      where: 'email = ?',
      whereArgs: [normalizeEmail(email)],
    );
    if (rows.isEmpty) {
      throw const AppException('Invalid email or password.');
    }
    final row = rows.first;
    final salt = row['salt'] as String;
    final hash = row['password_hash'] as String;
    if (!await _hasher.verify(password, salt, hash)) {
      throw const AppException('Invalid email or password.');
    }
    if (_hasher.needsRehash(hash)) {
      final newSalt = _hasher.generateSalt();
      await db.update(
        'owners',
        {
          'password_hash': await _hasher.hash(password, newSalt),
          'salt': newSalt,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    return _start(row);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    await _session.clear();
  }

  Future<AppUser> _start(Map<String, Object?> row) async {
    final user = _toUser(row);
    await _session.writeActiveAccountId(user.id);
    _current = user;
    return user;
  }

  static String normalizeEmail(String email) => email.toLowerCase().trim();

  static AppUser _toUser(Map<String, Object?> row) => AppUser(
    id: row['id'] as String,
    email: row['email'] as String,
    fullName: row['full_name'] as String,
    role: AccountRole.parse(row['role']),
  );
}
