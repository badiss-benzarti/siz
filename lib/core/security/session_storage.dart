import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists which account (owner, barber or client) is signed in on this
/// device.
abstract class SessionStorage {
  Future<String?> readActiveAccountId();
  Future<void> writeActiveAccountId(String ownerId);
  Future<void> clear();
}

/// [SessionStorage] backed by the platform keystore / keychain.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const String _activeAccountIdKey = 'siz_active_account_id';

  @override
  Future<String?> readActiveAccountId() =>
      _storage.read(key: _activeAccountIdKey);

  @override
  Future<void> writeActiveAccountId(String ownerId) =>
      _storage.write(key: _activeAccountIdKey, value: ownerId);

  @override
  Future<void> clear() => _storage.delete(key: _activeAccountIdKey);
}

/// Non-persistent [SessionStorage], used by tests.
class InMemorySessionStorage implements SessionStorage {
  String? _ownerId;

  @override
  Future<String?> readActiveAccountId() async => _ownerId;

  @override
  Future<void> writeActiveAccountId(String ownerId) async => _ownerId = ownerId;

  @override
  Future<void> clear() async => _ownerId = null;
}
