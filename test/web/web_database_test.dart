@TestOn('browser')
library;

import 'package:siz/core/database/database_service.dart';
import 'package:siz/core/security/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void main() {
  test('SQLite (WebAssembly) opens, migrates and stores rows', () async {
    // Tests are not served with the shared worker, so run SQLite in-page.
    final db = DatabaseService(
      factory: createDatabaseFactoryFfiWeb(
        options: SqfliteFfiWebOptions(
          sqlite3WasmUri: Uri.parse('/sqlite3.wasm'),
        ),
        noWebWorker: true,
      ),
      path: 'web_test_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final conn = await db.database;
    expect(await conn.getVersion(), DatabaseService.schemaVersion);
    await conn.insert('owners', {
      'id': 'o1',
      'email': 'a@b.co',
      'password_hash': 'h',
      'salt': 's',
      'full_name': 'A',
      'created_at': DateTime.now().toIso8601String(),
    });
    expect(await conn.query('owners'), hasLength(1));
    await db.close();
  });

  test('password hashing works without isolates', () async {
    const hasher = PasswordHasher(iterations: 1000);
    final hash = await hasher.hash('password123', 'salt');
    expect(await hasher.verify('password123', 'salt', hash), isTrue);
  });
}
