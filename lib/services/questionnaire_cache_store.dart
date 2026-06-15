import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cuestionario.dart';
import 'database_service.dart';

class QuestionnaireCacheEntry {
  QuestionnaireCacheEntry({
    required this.cuestionario,
    required this.preguntas,
  });

  final Cuestionario cuestionario;
  final List<Pregunta> preguntas;
}

class QuestionnaireCacheStore {
  QuestionnaireCacheStore({DatabaseService? dbService})
      : _dbService = dbService ?? GetIt.I<DatabaseService>();

  final DatabaseService _dbService;
  static const String _table = 'questionnaire_cache';

  Future<void> save({
    required Cuestionario cuestionario,
    required List<Pregunta> preguntas,
  }) async {
    final db = await _dbService.database;
    final cuestionarioJson = jsonEncode(cuestionario.toJson());
    final preguntasJson = jsonEncode(preguntas.map((p) => p.toJson()).toList());
    await db.insert(
      _table,
      {
        'cuestionario_id': cuestionario.id,
        'cuestionario_payload': cuestionarioJson,
        'preguntas_payload': preguntasJson,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<QuestionnaireCacheEntry?> loadLatest() async {
    final db = await _dbService.database;
    final rows = await db.query(
      _table,
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final cuestionarioPayload = row['cuestionario_payload'] as String?;
    final preguntasPayload = row['preguntas_payload'] as String?;
    if (cuestionarioPayload == null || preguntasPayload == null) return null;
    final cuestionarioJson = jsonDecode(cuestionarioPayload) as Map<String, dynamic>;
    final preguntasJson = jsonDecode(preguntasPayload) as List<dynamic>;
    final cuestionario = Cuestionario.fromJson(cuestionarioJson);
    final preguntas = preguntasJson
        .map((e) => Pregunta.fromJson(e as Map<String, dynamic>))
        .toList();
    return QuestionnaireCacheEntry(cuestionario: cuestionario, preguntas: preguntas);
  }
}
