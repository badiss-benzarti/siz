import 'package:siz/core/cloud/cloud_auth.dart';
import 'package:siz/core/errors/app_exception.dart';

const offlineError = AppException('No internet connection.');

/// In-memory stand-in for Supabase Auth.
class FakeCloudAuth implements CloudAuth {
  final _accounts = <String, (CloudUser, String)>{};
  bool requireEmailConfirmation = false;
  bool offline = false;
  int calls = 0;

  @override
  CloudUser? currentUser;

  @override
  Future<CloudUser?> signUp({
    required String email,
    required String password,
    required String fullName,
    required AccountRole role,
  }) async {
    calls++;
    if (offline) throw offlineError;
    if (_accounts.containsKey(email)) {
      throw const AppException('An account with this email already exists.');
    }
    final user = CloudUser(
      id: '00000000-0000-4000-8000-${_accounts.length.toString().padLeft(12, '0')}',
      email: email,
      fullName: fullName,
      role: role,
    );
    _accounts[email] = (user, password);
    if (requireEmailConfirmation) return null;
    return currentUser = user;
  }

  @override
  Future<CloudUser> signIn({
    required String email,
    required String password,
  }) async {
    calls++;
    if (offline) throw offlineError;
    final account = _accounts[email];
    if (account == null || account.$2 != password) {
      throw const AppException('Invalid email or password.');
    }
    return currentUser = account.$1;
  }

  @override
  Future<void> signOut() async => currentUser = null;
}
