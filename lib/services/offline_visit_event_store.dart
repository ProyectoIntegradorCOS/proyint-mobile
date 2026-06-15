import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';

class OfflineVisitEvent {
  OfflineVisitEvent({
    required this.id,
    required this.visitId,
    required this.eventType,
    required this.timestamp,
    this.latitude,
    this.longitude,
    required this.syncStatus,
    required this.attempts,
    this.lastError,
  });

  final int id;
  final int visitId;
  final String eventType;
  final String timestamp;
  final double? latitude;
  final double? longitude;
  final String syncStatus;
  final int attempts;
  final String? lastError;

  factory OfflineVisitEvent.fromRow(Map<String, dynamic> row) {
    return OfflineVisitEvent(
      id: row['id'] as int,
      visitId: row['visit_id'] as int,
      eventType: row['event_type'] as String,
      timestamp: row['timestamp'] as String,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      syncStatus: row['sync_status'] as String,
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      lastError: row['last_error'] as String?,
    );
  }
}

class OfflineVisitEventStore {
  OfflineVisitEventStore({DatabaseService? dbService})
      : _dbService = dbService ?? GetIt.I<DatabaseService>();

  final DatabaseService _dbService;
  static const String _table = 'offline_visit_events';

  Future<int> enqueue({
    required int visitId,
    required String eventType,
    required DateTime timestamp,
    double? latitude,
    double? longitude,
  }) async {
    final db = await _dbService.database;
    return db.insert(_table, {
      'visit_id': visitId,
      'event_type': eventType,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'sync_status': 'pending',
      'attempts': 0,
      'last_error': null,
    });
  }

  Future<List<OfflineVisitEvent>> fetchPending() async {
    final db = await _dbService.database;
    final rows = await db.query(
      _table,
      where: "sync_status IN ('pending', 'error')",
      orderBy: 'visit_id ASC, id ASC',
    );
    return rows.map(OfflineVisitEvent.fromRow).toList();
  }

  Future<Set<int>> fetchPendingVisitIds() async {
    final db = await _dbService.database;
    final rows = await db.query(
      _table,
      columns: ['visit_id'],
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'visit_id ASC',
    );
    return rows
        .map((row) => (row['visit_id'] as num).toInt())
        .toSet();
  }

  Future<int> countPending() async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(1) as cnt FROM $_table WHERE sync_status = ?',
      ['pending'],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<void> markSynced(int id) async {
    final db = await _dbService.database;
    await db.update(
      _table,
      {'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markError(int id, String error) async {
    final db = await _dbService.database;
    await db.update(
      _table,
      {
        'sync_status': 'error',
        'attempts': (await _currentAttempts(id)) + 1,
        'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> _currentAttempts(int id) async {
    final db = await _dbService.database;
    final rows = await db.query(_table, columns: ['attempts'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return 0;
    return (rows.first['attempts'] as num?)?.toInt() ?? 0;
  }
}
