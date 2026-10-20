import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo/demo_seeder.dart';
import '../../core/errors/app_exception.dart';
import '../../core/providers/core_providers.dart';
import '../auth_onboarding/presentation/auth_providers.dart';
import '../barber_app/barber_session.dart';
import '../client_app/client_session.dart';
import 'entry_role.dart';

/// "Try the demo": creates the demo salons and accounts on this phone the
/// first time, then signs in to any of them with one tap. The emails and
/// passwords are shown so they can also be typed on the sign-in screens.
Future<void> showDemoAccounts(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _DemoAccountsSheet(),
  );
}

class _DemoAccountsSheet extends ConsumerStatefulWidget {
  const _DemoAccountsSheet();

  @override
  ConsumerState<_DemoAccountsSheet> createState() => _DemoAccountsSheetState();
}

class _DemoAccountsSheetState extends ConsumerState<_DemoAccountsSheet> {
  late final Future<void> _ready = _prepare();
  bool _signingIn = false;
  String? _error;

  Future<void> _prepare() async {
    await ref.read(demoSeederProvider).ensureDemoAccount();
    // Creating the demo signs nobody in.
    final auth = ref.read(accountAuthProvider);
    if (auth.currentUser == null) await auth.signOut();
  }

  Future<void> _signIn(DemoAccount account) async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    final roles = ref.read(entryRoleProvider.notifier);
    final bool ok;
    switch (account.role) {
      case 'owner':
        roles.choose(EntryRole.owner);
        ok = await ref
            .read(authProvider.notifier)
            .login(email: account.email, password: account.password);
      case 'barber':
        roles.choose(EntryRole.barber);
        ok = await ref
            .read(barberSessionProvider.notifier)
            .login(email: account.email, password: account.password);
      default:
        roles.choose(EntryRole.client);
        ok = await ref
            .read(clientSessionProvider.notifier)
            .login(email: account.email, password: account.password);
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      roles.reset();
      setState(() {
        _signingIn = false;
        _error = 'Could not sign in. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(describeError(snapshot.error!)),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.black),
                  SizedBox(height: 16),
                  Text('Preparing the demo salons on this phone…'),
                ],
              ),
            );
          }
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Text(
                'Demo accounts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap one to sign in. Everything is stored on this phone.',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ),
              const SizedBox(height: 8),
              for (final a in DemoSeeder.accounts)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    enabled: !_signingIn,
                    leading: CircleAvatar(
                      backgroundColor: Colors.black,
                      child: Icon(
                        switch (a.role) {
                          'owner' => Icons.storefront_outlined,
                          'barber' => Icons.content_cut,
                          _ => Icons.person_outline,
                        },
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '${a.name} · ${a.role[0].toUpperCase()}'
                      '${a.role.substring(1)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${a.note}\n${a.email} / ${a.password}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.login),
                    onTap: () => _signIn(a),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
