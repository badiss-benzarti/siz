import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/account_auth.dart';
import 'core/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Everything is on this phone: the SQLite database (picked per platform
  // by DatabaseService) and the signed-in account, restored here.
  final container = ProviderContainer();
  final auth = container.read(accountAuthProvider);
  if (auth is LocalAccountAuth) await auth.restore();
  runApp(
    UncontrolledProviderScope(container: container, child: const SizApp()),
  );
}
