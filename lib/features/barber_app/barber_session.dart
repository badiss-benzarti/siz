import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_auth.dart';
import '../../core/errors/app_exception.dart';
import '../../core/providers/core_providers.dart';
import 'barber_link.dart';

class BarberSessionState {
  const BarberSessionState({
    this.user,
    this.link,
    this.invite,
    this.isLoading = false,
    this.errorMessage,
    this.infoMessage,
  });

  /// The signed-in barber account, if any.
  final AppUser? user;

  /// The salon the account is linked to; null until it joins one.
  final BarberLink? link;

  /// A checked code, before the account is created with it.
  final InvitePreview? invite;
  final bool isLoading;
  final String? errorMessage;
  final String? infoMessage;

  bool get isSignedIn => user != null;
}

/// The barber side's session. A new barber starts with the code from their
/// salon owner, which shows the salon and the name the owner registered;
/// only then do they create their account, which joins the salon right
/// away. The barber sees their salon's data from this device's database.
final barberSessionProvider =
    NotifierProvider<BarberSessionNotifier, BarberSessionState>(
      BarberSessionNotifier.new,
    );

class BarberSessionNotifier extends Notifier<BarberSessionState> {
  AccountAuth get _auth => ref.read(accountAuthProvider);
  BarberLinkRepository get _links => ref.read(barberLinkRepositoryProvider);

  static const _invalidCode =
      'This code is not valid or has expired. Ask your salon for a new one.';

  @override
  BarberSessionState build() {
    final user = ref.read(accountAuthProvider).currentUser;
    if (user == null || user.role != AccountRole.barber) {
      return const BarberSessionState();
    }
    Future.microtask(refresh);
    return BarberSessionState(user: user, isLoading: true);
  }

  /// Reloads which salon this account belongs to.
  Future<void> refresh() async {
    final user = state.user;
    if (user == null) return;
    state = BarberSessionState(user: user, link: state.link, isLoading: true);
    try {
      final link = await _links.myLink(user.id);
      state = BarberSessionState(user: user, link: link);
    } catch (e) {
      state = BarberSessionState(
        user: user,
        link: state.link,
        errorMessage: describeError(e),
      );
    }
  }

  /// Step 1 for a new barber: what does this code open?
  Future<bool> checkCode(String code) async {
    state = const BarberSessionState(isLoading: true);
    try {
      final invite = await _links.preview(code);
      state = invite == null
          ? const BarberSessionState(errorMessage: _invalidCode)
          : BarberSessionState(invite: invite);
      return invite != null;
    } catch (e) {
      state = BarberSessionState(errorMessage: describeError(e));
      return false;
    }
  }

  /// Back to entering a code.
  void clearInvite() => state = const BarberSessionState();

  /// Step 2: creates the account under the name the owner registered, and
  /// joins the salon with the checked code.
  Future<bool> registerWithCode({
    required String email,
    required String password,
  }) async {
    final invite = state.invite;
    if (invite == null) return false;
    state = BarberSessionState(invite: invite, isLoading: true);
    final normalized = email.toLowerCase().trim();

    final AppUser user;
    try {
      user = await _auth.signUp(
        email: normalized,
        password: password,
        fullName: invite.barberName,
        role: AccountRole.barber,
      );
    } catch (e) {
      state = BarberSessionState(
        invite: invite,
        errorMessage: describeError(e),
      );
      return false;
    }

    try {
      final link = await _links.join(user.id, invite.code);
      state = BarberSessionState(user: user, link: link);
      return true;
    } catch (e) {
      // The account exists; the code screen lets them try another code.
      state = BarberSessionState(user: user, errorMessage: describeError(e));
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = const BarberSessionState(isLoading: true);
    try {
      final user = await _auth.signIn(
        email: email.toLowerCase().trim(),
        password: password,
      );
      if (user.role != AccountRole.barber) {
        await _auth.signOut();
        throw const AppException(
          'This is not a barber account. Go back and choose your space.',
        );
      }
      state = BarberSessionState(user: user);
      await refresh();
      return true;
    } catch (e) {
      state = BarberSessionState(errorMessage: describeError(e));
      return false;
    }
  }

  /// For a signed-in barber without a salon (e.g. after leaving one).
  Future<bool> join(String code) async {
    final user = state.user;
    if (user == null) return false;
    state = BarberSessionState(user: user, isLoading: true);
    try {
      final link = await _links.join(user.id, code);
      state = BarberSessionState(user: user, link: link);
      return true;
    } on AppException catch (e) {
      state = BarberSessionState(user: user, errorMessage: e.message);
      return false;
    }
  }

  /// Asks the owner for another name; it applies once they accept.
  Future<void> requestNameChange(String name) async {
    await _links.requestNameChange(name);
    await refresh();
  }

  /// Leaves the salon: the account stays, the salon's data is no longer
  /// visible, and the salon keeps the roster entry and its history.
  Future<void> leave() async {
    final user = state.user;
    await _links.leave();
    state = BarberSessionState(user: user);
  }

  void clearMessages() {
    if (state.errorMessage == null && state.infoMessage == null) return;
    state = BarberSessionState(
      user: state.user,
      link: state.link,
      invite: state.invite,
    );
  }

  Future<void> logout() async {
    await _auth.signOut();
    state = const BarberSessionState();
  }
}
