/// Creates the public demo salon on the live server: a listed salon with a
/// team, prices, a month of sales, cuts in progress and clients waiting, so
/// the client map and the barber side have something real to show.
///
/// It is built with the app's own code (demo generator, first upload, sync)
/// under its own owner account, separate from the in-app demo whose password
/// is public. Runs only on request:
///
///   flutter test test/live/seed_demo_salon_test.dart \
///     --dart-define=SEED_DEMO=true --dart-define=DEMO_PASSWORD=YOUR_SECRET
///
/// Add --dart-define=DEMO_RESET=true to delete and rebuild it (e.g. to bring
/// its sales history up to date).
library;

import 'package:siz/core/cloud/cloud_auth.dart';
import 'package:siz/core/cloud/cloud_shop_repository.dart';
import 'package:siz/core/config/supabase_config.dart';
import 'package:siz/core/demo/demo_seeder.dart';
import 'package:siz/core/errors/app_exception.dart';
import 'package:siz/core/sync/supabase_sync_remote.dart';
import 'package:siz/core/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_database.dart';

const _enabled = bool.fromEnvironment('SEED_DEMO');
const _email = String.fromEnvironment(
  'DEMO_EMAIL',
  defaultValue: 'demo.salon@barberflow-test.com',
);
const _password = String.fromEnvironment('DEMO_PASSWORD');
const _reset = bool.fromEnvironment('DEMO_RESET');

SupabaseClient _client() => SupabaseClient(
  SupabaseConfig.url,
  SupabaseConfig.publishableKey,
  // No storage in tests, so no PKCE (the app gets storage from initialize).
  authOptions: const AuthClientOptions(
    autoRefreshToken: false,
    authFlowType: AuthFlowType.implicit,
  ),
);

void main() {
  test(
    'seed the public demo salon',
    () async {
      expect(
        _password.length,
        greaterThanOrEqualTo(12),
        reason: 'Pass a strong --dart-define=DEMO_PASSWORD.',
      );

      final client = _client();
      final auth = SupabaseCloudAuth(client);
      CloudUser user;
      try {
        user = await auth.signIn(email: _email, password: _password);
      } on AppException {
        final created = await auth.signUp(
          role: AccountRole.owner,
          email: _email,
          password: _password,
          fullName: 'BarberFlow Demo',
        );
        expect(created, isNotNull, reason: 'Turn off "Confirm email".');
        user = created!;
      }

      final cloudShops = SupabaseCloudShopRepository(client);
      final existing = await cloudShops.fetchOwnedShop(user.id);
      if (existing != null) {
        if (!_reset) {
          // ignore: avoid_print
          print(
            'Demo salon already on the server: ${existing.shop.name}. '
            'Pass DEMO_RESET=true to rebuild it.',
          );
          return;
        }
        await client.from('shops').delete().eq('id', existing.shop.id);
      }

      // Build it on a throwaway device database, as the app would.
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      await env.shops.signInCloudOwner(
        id: user.id,
        email: _email,
        fullName: 'BarberFlow Demo',
      );
      final shop = await DemoSeeder(
        dbService: env.db,
        shops: env.shops,
        floor: env.floor,
        queue: env.queue,
      ).populateShop(user.id);
      await env.shops.setShopListed(shopId: shop.id, isListed: true);

      await cloudShops.uploadShop((await env.shops.loadSnapshot(user.id))!);
      final engine = SyncEngine(
        dbService: env.db,
        remote: SupabaseSyncRemote(client),
      );
      // Rows refused for ordering reasons go through on the next round.
      for (var round = 0; round < 3; round++) {
        final report = await engine.push(shop.id);
        expect(report.offline, isFalse);
        if ((await engine.backlog(shop.id)).pending == 0) break;
      }
      final backlog = await engine.backlog(shop.id);
      expect(backlog.pending, 0, reason: backlog.lastError);

      // What anyone opening the client map now sees.
      final visitor = _client();
      final listed = await visitor
          .from('shops')
          .select('name, is_open, waiting_count, latitude, longitude')
          .eq('id', shop.id)
          .single();
      final barbers = await visitor
          .from('barbers')
          .select('name')
          .eq('shop_id', shop.id);
      final tickets = await client
          .from('tickets')
          .select('id')
          .eq('shop_id', shop.id);
      expect(listed['waiting_count'], 3);

      // ignore: avoid_print
      print(
        'Demo salon "${listed['name']}" is live at '
        '${listed['latitude']}, ${listed['longitude']}: '
        '${barbers.length} barbers, ${tickets.length} past sales, '
        '${listed['waiting_count']} waiting.',
      );
      await auth.signOut();
    },
    skip: _enabled ? false : 'Seeds the live server: pass SEED_DEMO=true',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
