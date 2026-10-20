import 'package:sqflite/sqflite.dart';

import '../sync/sync_schema.dart';

import 'database_platform_io.dart'
    if (dart.library.js_interop) 'database_platform_web.dart';

/// Owns the single SQLite connection used by the app: schema creation,
/// migrations and connection lifecycle.
///
/// On mobile and desktop the database lives in the app's private data
/// directory; in a browser it is SQLite (WebAssembly) persisted in IndexedDB.
/// It is not encrypted at rest; protection relies on the platform sandbox.
class DatabaseService {
  DatabaseService({this._factory, this._path});

  final DatabaseFactory? _factory;
  final String? _path;
  Future<Database>? _opening;

  static const String _dbFileName = 'siz.db';
  static const int schemaVersion = 6;

  /// The open database. Concurrent callers share the same connection.
  Future<Database> get database {
    return _opening ??= _open().catchError((Object error) {
      _opening = null;
      throw error;
    });
  }

  Future<Database> _open() async {
    final factory = _factory ?? platformDatabaseFactory();
    final path = _path ?? await platformDatabasePath(_dbFileName);

    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
    // `journal_mode` returns a row, so it must go through rawQuery.
    await db.rawQuery('PRAGMA journal_mode = WAL;');
  }

  /// Creates the version 1 schema, then applies every migration so new
  /// installs and upgraded installs end up with identical schemas.
  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE owners (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        full_name TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE shops (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        name TEXT NOT NULL,
        address TEXT NOT NULL,
        phone TEXT NOT NULL,
        total_chairs INTEGER NOT NULL DEFAULT 8,
        created_at TEXT NOT NULL,
        FOREIGN KEY (owner_id) REFERENCES owners (id) ON DELETE CASCADE
      );
    ''');

    batch.execute('''
      CREATE TABLE barbers (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        commission_rate REAL NOT NULL DEFAULT 0.60,
        is_on_duty INTEGER NOT NULL DEFAULT 1,
        assigned_chair INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (shop_id) REFERENCES shops (id) ON DELETE CASCADE
      );
    ''');

    batch.execute('''
      CREATE TABLE chairs (
        chair_number INTEGER NOT NULL,
        shop_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'empty',
        active_barber_id TEXT,
        active_client_name TEXT,
        active_ticket_id TEXT,
        service_start_time TEXT,
        PRIMARY KEY (shop_id, chair_number),
        FOREIGN KEY (shop_id) REFERENCES shops (id) ON DELETE CASCADE,
        FOREIGN KEY (active_barber_id) REFERENCES barbers (id) ON DELETE SET NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE services (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        duration_minutes INTEGER NOT NULL DEFAULT 30,
        FOREIGN KEY (shop_id) REFERENCES shops (id) ON DELETE CASCADE
      );
    ''');

    batch.execute('''
      CREATE TABLE tickets (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        client_name TEXT NOT NULL,
        client_phone TEXT,
        barber_id TEXT NOT NULL,
        chair_number INTEGER NOT NULL,
        service_names TEXT NOT NULL,
        total_price REAL NOT NULL,
        barber_cut REAL NOT NULL,
        shop_cut REAL NOT NULL,
        tip REAL NOT NULL DEFAULT 0.0,
        payment_method TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (shop_id) REFERENCES shops (id) ON DELETE CASCADE,
        FOREIGN KEY (barber_id) REFERENCES barbers (id) ON DELETE CASCADE
      );
    ''');

    batch.execute('''
      CREATE TABLE queue (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        client_name TEXT NOT NULL,
        client_phone TEXT,
        requested_barber_id TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'waiting',
        created_at TEXT NOT NULL,
        FOREIGN KEY (shop_id) REFERENCES shops (id) ON DELETE CASCADE,
        FOREIGN KEY (requested_barber_id) REFERENCES barbers (id) ON DELETE SET NULL
      );
    ''');

    await batch.commit(noResult: true);
    await _onUpgrade(db, 1, version);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2 && newVersion >= 2) {
      await _migrateToV2(db);
    }
    if (oldVersion < 3 && newVersion >= 3) {
      await _migrateToV3(db);
    }
    if (oldVersion < 4 && newVersion >= 4) {
      await _migrateToV4(db);
    }
    if (oldVersion < 5 && newVersion >= 5) {
      await _migrateToV5(db);
    }
    if (oldVersion < 6 && newVersion >= 6) {
      await _migrateToV6(db);
    }
  }

  /// v2: barbers are archived instead of deleted (deleting would cascade to
  /// their financial tickets), plus indexes for the hot queries.
  Future<void> _migrateToV2(Database db) async {
    final batch = db.batch();
    batch.execute(
      'ALTER TABLE barbers ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_tickets_shop_time ON tickets (shop_id, timestamp);',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_queue_shop_status ON queue (shop_id, status, created_at);',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_barbers_shop ON barbers (shop_id);',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_shops_owner ON shops (owner_id);',
    );
    await batch.commit(noResult: true);
  }

  /// v3: change capture for cloud sync (see [SyncSchema]).
  Future<void> _migrateToV3(Database db) async {
    final batch = db.batch();
    SyncSchema.createStatements().forEach(batch.execute);
    await batch.commit(noResult: true);
  }

  /// v4: where the salon is and whether clients can see it (client map).
  Future<void> _migrateToV4(Database db) async {
    final batch = db.batch()
      ..execute('ALTER TABLE shops ADD COLUMN latitude REAL;')
      ..execute('ALTER TABLE shops ADD COLUMN longitude REAL;')
      ..execute(
        'ALTER TABLE shops ADD COLUMN is_open INTEGER NOT NULL DEFAULT 1;',
      )
      ..execute(
        'ALTER TABLE shops ADD COLUMN is_listed INTEGER NOT NULL DEFAULT 0;',
      );
    await batch.commit(noResult: true);
  }

  /// v5: which barbers linked their own account (barber app).
  Future<void> _migrateToV5(Database db) async {
    await db.execute('ALTER TABLE barbers ADD COLUMN profile_id TEXT;');
  }

  /// v6: a new name a barber asked for, waiting for the owner.
  Future<void> _migrateToV6(Database db) async {
    await db.execute('ALTER TABLE barbers ADD COLUMN requested_name TEXT;');
  }

  /// Closes the connection; the next access reopens it.
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening == null) return;
    final db = await opening;
    if (db.isOpen) await db.close();
  }
}
