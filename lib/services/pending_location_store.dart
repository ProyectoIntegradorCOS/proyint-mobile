import 'package:sqflite/sqflite.dart';
import '../models/pending_location.dart';
import 'database_service.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Almacén local para ubicaciones pendientes de envío][obj: PendingLocationStore]
class PendingLocationStore {
  static const String _tableName = 'pending_locations';
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get database async {
    return _dbService.database;
  }


  Future<int> insert(PendingLocation location) async {
    final db = await database;
    return db.insert(_tableName, location.toMap());
  }

  Future<List<PendingLocation>> getAll() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_tableName);
    return List.generate(maps.length, (i) => PendingLocation.fromMap(maps[i]));
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Obtiene lote por usuario (evita mezclar ubicaciones entre sesiones)][obj: PendingLocationStore.getBatchForSubject]
  Future<List<PendingLocation>> getBatchForSubject(
    String saaSubject,
    int limit,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'saaSubject = ?',
      whereArgs: [saaSubject],
      limit: limit,
      orderBy: 'timestamp_epoch_ms ASC, id ASC',
    );
    return List.generate(maps.length, (i) => PendingLocation.fromMap(maps[i]));
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:30 UTC-5 (Lima)][desc: Obtiene todas las ubicaciones pendientes por usuario (ordenadas)][obj: PendingLocationStore.getAllForSubject]
  Future<List<PendingLocation>> getAllForSubject(String saaSubject) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'saaSubject = ?',
      whereArgs: [saaSubject],
      orderBy: 'timestamp_epoch_ms ASC, id ASC',
    );
    return List.generate(maps.length, (i) => PendingLocation.fromMap(maps[i]));
  }

  Future<List<PendingLocation>> getBatch(int limit) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      limit: limit,
      orderBy: 'timestamp_epoch_ms ASC, id ASC',
    );
    return List.generate(maps.length, (i) => PendingLocation.fromMap(maps[i]));
  }

  Future<int> deleteBatch(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    return db.delete(
      _tableName,
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Conteo por usuario para control de batchSize y flushing][obj: PendingLocationStore.countForSubject]
  Future<int> countForSubject(String saaSubject) async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $_tableName WHERE saaSubject = ?',
            [saaSubject],
          ),
        ) ??
        0;
  }

  Future<int> count() async {
    final db = await database;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_tableName')) ??
        0;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Purga por retención (maxAge) y cap (maxRows) por usuario][obj: PendingLocationStore.purgeForSubject]
  Future<void> purgeForSubject(
    String saaSubject, {
    required Duration maxAge,
    required int maxRows,
  }) async {
    final db = await database;

    // Backfill suave de epoch para filas antiguas (evita comparar strings ISO).
    await _backfillEpochForSubject(db, saaSubject, limit: 500);

    final cutoffMs = DateTime.now().millisecondsSinceEpoch - maxAge.inMilliseconds;
    await db.delete(
      _tableName,
      where:
          'saaSubject = ? AND timestamp_epoch_ms IS NOT NULL AND timestamp_epoch_ms < ?',
      whereArgs: [saaSubject, cutoffMs],
    );

    final count = await countForSubject(saaSubject);
    final excess = count - maxRows;
    if (excess <= 0) return;

    // Eliminar los más antiguos: epoch asc (nulls primero), luego id asc.
    final rows = await db.rawQuery(
      '''
      SELECT id FROM $_tableName
      WHERE saaSubject = ?
      ORDER BY COALESCE(timestamp_epoch_ms, 0) ASC, id ASC
      LIMIT ?
      ''',
      [saaSubject, excess],
    );
    final ids = rows.map((e) => (e['id'] as num).toInt()).toList();
    await deleteBatch(ids);
  }

  Future<void> _backfillEpochForSubject(
    Database db,
    String saaSubject, {
    required int limit,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT id, timestamp FROM $_tableName
      WHERE saaSubject = ? AND (timestamp_epoch_ms IS NULL OR timestamp_epoch_ms = 0)
      ORDER BY id ASC
      LIMIT ?
      ''',
      [saaSubject, limit],
    );
    if (rows.isEmpty) return;

    final batch = db.batch();
    for (final r in rows) {
      final id = (r['id'] as num).toInt();
      final ts = r['timestamp']?.toString();
      if (ts == null || ts.isEmpty) continue;
      final parsed = DateTime.tryParse(ts);
      if (parsed == null) continue;
      batch.update(
        _tableName,
        {'timestamp_epoch_ms': parsed.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Obtiene min/max timestamp (string) para trazabilidad de cola por usuario][obj: PendingLocationStore.getMinMaxTimestampsForSubject]
  Future<(String, String)?> getMinMaxTimestampsForSubject(String saaSubject) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT MIN(timestamp) AS minTs, MAX(timestamp) AS maxTs
      FROM $_tableName
      WHERE saaSubject = ?
      ''',
      [saaSubject],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final minTs = r['minTs']?.toString();
    final maxTs = r['maxTs']?.toString();
    if (minTs == null || maxTs == null) return null;
    return (minTs, maxTs);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Purga global de filas antiguas sin importar el usuario (limpia puntos huérfanos de sesiones anteriores en el mismo equipo)][obj: PendingLocationStore.purgeAllOlderThan]
  Future<int> purgeAllOlderThan(Duration maxAge) async {
    final db = await database;
    final cutoffMs = DateTime.now().millisecondsSinceEpoch - maxAge.inMilliseconds;
    return db.delete(
      _tableName,
      where: 'timestamp_epoch_ms IS NOT NULL AND timestamp_epoch_ms < ?',
      whereArgs: [cutoffMs],
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Peek del registro más antiguo para depurar si la cola corresponde a otro usuario][obj: PendingLocationStore.peekOldest]
  Future<String?> peekOldest() async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT id, saaSubject, timestamp
      FROM $_tableName
      ORDER BY id ASC
      LIMIT 1
      ''',
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final id = r['id']?.toString();
    final subject = r['saaSubject']?.toString();
    final ts = r['timestamp']?.toString();
    return 'id=$id saaSubject=$subject ts=$ts';
  }
}
