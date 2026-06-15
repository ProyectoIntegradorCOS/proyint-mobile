import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cuestionario.dart';
import 'database_service.dart';

class OfflineQuestionnaireRecord {
  OfflineQuestionnaireRecord({
    required this.id,
    required this.visitId,
    required this.cuestionarioId,
    required this.payload,
    required this.createdAt,
    required this.syncStatus,
    required this.attempts,
    this.lastError,
  });

  final int id;
  final int visitId;
  final int cuestionarioId;
  final String payload;
  final String createdAt;
  final String syncStatus;
  final int attempts;
  final String? lastError;

  factory OfflineQuestionnaireRecord.fromRow(Map<String, dynamic> row) {
    return OfflineQuestionnaireRecord(
      id: row['id'] as int,
      visitId: row['visit_id'] as int,
      cuestionarioId: row['cuestionario_id'] as int,
      payload: row['payload'] as String,
      createdAt: row['created_at'] as String,
      syncStatus: row['sync_status'] as String,
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      lastError: row['last_error'] as String?,
    );
  }

  List<RespuestaPayload> toRespuestas() {
    final list = jsonDecode(payload) as List<dynamic>;
    return list
        .map((e) => e as Map<String, dynamic>)
        .map(
          (e) => RespuestaPayload(
            idPersona: (e['idPersona'] as num).toInt(),
            idCuestionario: (e['idCuestionario'] as num).toInt(),
            idPregunta: (e['idPregunta'] as num).toInt(),
            idItem: (e['idItem'] as num).toInt(),
            textoPregunta: e['textoPregunta'] as String,
            respuesta: e['respuesta'] as String,
            estado: (e['estado'] as num).toInt(),
          ),
        )
        .toList();
  }
}

class OfflineQuestionnaireStore {
  OfflineQuestionnaireStore({DatabaseService? dbService})
      : _dbService = dbService ?? GetIt.I<DatabaseService>();

  final DatabaseService _dbService;
  static const String _table = 'offline_questionnaires';

  Future<int> enqueue({
    required int visitId,
    required int cuestionarioId,
    required List<RespuestaPayload> respuestas,
  }) async {
    final db = await _dbService.database;
    final payload = jsonEncode(respuestas.map((e) => e.toJson()).toList());
    return db.insert(
      _table,
      {
        'visit_id': visitId,
        'cuestionario_id': cuestionarioId,
        'payload': payload,
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'pending',
        'attempts': 0,
        'last_error': null,
      },
    );
  }

  Future<List<OfflineQuestionnaireRecord>> fetchPending() async {
    final db = await _dbService.database;
    final rows = await db.query(
      _table,
      where: "sync_status IN ('pending', 'error')",
      orderBy: 'visit_id ASC, id ASC',
    );
    return rows.map(OfflineQuestionnaireRecord.fromRow).toList();
  }

  Future<Map<int, int>> fetchPendingCountsByVisit() async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      'SELECT visit_id, COUNT(1) as cnt FROM $_table WHERE sync_status = ? GROUP BY visit_id',
      ['pending'],
    );
    final result = <int, int>{};
    for (final row in rows) {
      final visitId = (row['visit_id'] as num).toInt();
      final count = (row['cnt'] as num).toInt();
      result[visitId] = count;
    }
    return result;
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
