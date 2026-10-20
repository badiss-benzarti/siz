import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_auth.dart';
import '../../core/errors/app_exception.dart';
import '../../core/providers/core_providers.dart';

class ClientSessionState {
  const ClientSessionState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
    this.infoMessage,
  });

  /// The signed-in client account; null while browsing as a guest.
  final AppUser? user;
  final bool isLoading;
  final String? errorMessage;
  final String? infoMessage;

  bool get isSignedIn => user != null;
}

/// The client side's session. Clients browse salons as guests; an account is
/// for joining a queue, booking, commenting and rating.
final clientSessionProvider =
    NotifierProvider<ClientSessionNotifier, ClientSessionState>(
      ClientSessionNotifier.new,
    );

class ClientSessionNotifier extends Notifier<ClientSessionState> {
  AccountAuth get _auth => ref.read(accountAuthProvider);

  @override
  ClientSessionState build() {
    final user = ref.read(accountAuthProvider).currentUser;
    return user?.role == AccountRole.client
        ? ClientSessionState(user: user)
        : const ClientSessionState();
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    if (fullName.trim().isEmpty) {
      state = const ClientSessionState(errorMessage: 'Please enter your name.');
      return false;
    }
    state = const ClientSessionState(isLoading: true);
    final normalized = email.toLowerCase().trim();
    try {
      final user = await _auth.signUp(
        email: normalized,
        password: password,
        fullName: fullName.trim(),
        role: AccountRole.client,
      );
      state = ClientSessionState(user: user);
      return true;
    } catch (e) {
      state = ClientSessionState(errorMessage: describeError(e));
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = const ClientSessionState(isLoading: true);
    try {
      final user = await _auth.signIn(
        email: email.toLowerCase().trim(),
        password: password,
      );
      if (user.role != AccountRole.client) {
        await _auth.signOut();
        throw const AppException(
          'This is not a client account. Go back and choose your space.',
        );
      }
      state = ClientSessionState(user: user);
      return true;
    } catch (e) {
      state = ClientSessionState(errorMessage: describeError(e));
      return false;
    }
  }

  void clearMessages() {
    if (state.errorMessage == null && state.infoMessage == null) return;
    state = ClientSessionState(user: state.user);
  }

  Future<void> logout() async {
    await _auth.signOut();
    state = const ClientSessionState();
  }
}
