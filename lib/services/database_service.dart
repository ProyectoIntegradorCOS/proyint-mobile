import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Servicio centralizado para gestión de base de datos SQLite][obj: DatabaseService]
import '../utils/logger.dart';

class DatabaseService {
  Database? _database;

  DatabaseService();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'tracking_store.db');
    return openDatabase(
      path,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Agrega columna timestamp_epoch_ms para retención/purga eficiente][obj: DatabaseService version 3]
      version: 6,
      onCreate: (db, version) async {
        await _createPendingLocationsTable(db);
        await _createGeocodingCacheTable(db);
        await _createVisitPlanCacheTable(db);
        await _createOfflineVisitEventsTable(db);
        await _createOfflineQuestionnairesTable(db);
        await _createQuestionnaireCacheTable(db);
      },
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Loguea versión de BD al abrir para diagnosticar si la migración se aplicó][obj: DatabaseService.onOpen version log]
      onOpen: (db) async {
        final version = await db.getVersion();
        logInfo('DatabaseService: BD abierta', details: 'version=$version');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        logInfo('DatabaseService: migrando BD', details: 'oldVersion=$oldVersion newVersion=$newVersion');
        if (oldVersion < 2) {
          await _createGeocodingCacheTable(db);
        }
        if (oldVersion < 3) {
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Soporta retención/purga añadiendo timestamp_epoch_ms en pending_locations][obj: DatabaseService onUpgrade v3]
          await db.execute(
            'ALTER TABLE pending_locations ADD COLUMN timestamp_epoch_ms INTEGER',
          );
        }
        if (oldVersion < 4) {
          await _createVisitPlanCacheTable(db);
          await _createOfflineVisitEventsTable(db);
          await _createOfflineQuestionnairesTable(db);
        }
        if (oldVersion < 5) {
          await _createQuestionnaireCacheTable(db);
        }
        if (oldVersion >= 4 && oldVersion < 6) {
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Agrega user_id a visit_plan_cache para aislar el plan cacheado por usuario y evitar que el siguiente login vea el plan del anterior][obj: DatabaseService onUpgrade v6]
          await db.execute(
            'ALTER TABLE visit_plan_cache ADD COLUMN user_id TEXT',
          );
        }
      },
    );
  }

  Future<void> _createPendingLocationsTable(Database db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS pending_locations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        saaSubject TEXT,
        latitude REAL,
        longitude REAL,
        timestamp TEXT,
        timestamp_epoch_ms INTEGER,
        accuracy REAL,
        altitude REAL,
        speed REAL,
        heading REAL,
        batteryLevel REAL,
        activityType TEXT
      )
      ''',
    );
  }

  Future<void> _createGeocodingCacheTable(Database db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS geocoding_cache(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL,
        longitude REAL,
        address TEXT,
        timestamp INTEGER
      )
      ''',
    );
    // Index for faster spatial-like lookups (though we'll do simple bounding box or distance check in code/query)
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_geo_lat_lng ON geocoding_cache(latitude, longitude)',
    );
  }

  Future<void> _createVisitPlanCacheTable(Database db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS visit_plan_cache(
        plan_id INTEGER PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        user_id TEXT
      )
      ''',
    );
  }

  Future<void> _createOfflineVisitEventsTable(Database db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS offline_visit_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        sync_status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
      ''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_offline_visit_events_status ON offline_visit_events(sync_status, visit_id, id)',
    );
  }

  Future<void> _createOfflineQuestionnairesTable(Database db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS offline_questionnaires(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL,
        cuestionario_id INTEGER NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
      ''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_offline_questionnaires_status ON offline_questionnaires(sync_status, visit_id, id)',
    );
  }

  Future<void> _createQuestionnaireCacheTable(Database db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS questionnaire_cache(
        cuestionario_id INTEGER PRIMARY KEY,
        cuestionario_payload TEXT NOT NULL,
        preguntas_payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
      ''',
    );
  }

  Future<void> clearDatabase() async {
    try {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
    } catch (_) {
      _database = null;
    }
    try {
      final path = join(await getDatabasesPath(), 'tracking_store.db');
      await deleteDatabase(path);
    } catch (_) {}
  }
}
