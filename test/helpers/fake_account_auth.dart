import 'package:siz/core/auth/account_auth.dart';
import 'package:siz/core/errors/app_exception.dart';

/// In-memory stand-in for the account store, for widget tests.
class FakeAccountAuth implements AccountAuth {
  final _accounts = <String, (AppUser, String)>{};
  int calls = 0;

  @override
  AppUser? currentUser;

  @override
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
    required AccountRole role,
  }) async {
    calls++;
    if (_accounts.containsKey(email)) {
      throw const AppException('An account with this email already exists.');
    }
    final user = AppUser(
      id: '00000000-0000-4000-8000-${_accounts.length.toString().padLeft(12, '0')}',
      email: email,
      fullName: fullName,
      role: role,
    );
    _accounts[email] = (user, password);
    return currentUser = user;
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    calls++;
    final account = _accounts[email];
    if (account == null || account.$2 != password) {
      throw const AppException('Invalid email or password.');
    }
    return currentUser = account.$1;
  }

  @override
  Future<void> signOut() async => currentUser = null;
}
