import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account_auth.dart';
import '../database/database_service.dart';
import '../security/password_hasher.dart';
import '../security/session_storage.dart';

/// The single database connection shared by every repository.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(service.close);
  return service;
});

final passwordHasherProvider = Provider<PasswordHasher>((ref) {
  return const PasswordHasher();
});

final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SecureSessionStorage();
});

/// Accounts of all three roles, on this device. `main()` restores the
/// signed-in account before the first screen.
final accountAuthProvider = Provider<AccountAuth>((ref) {
  return LocalAccountAuth(
    db: ref.watch(databaseServiceProvider),
    hasher: ref.watch(passwordHasherProvider),
    session: ref.watch(sessionStorageProvider),
  );
});
