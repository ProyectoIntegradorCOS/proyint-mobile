import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/visit_plan.dart';
import 'auth_service.dart';
import 'database_service.dart';

class VisitPlanCacheStore {
  VisitPlanCacheStore({DatabaseService? dbService})
      : _dbService = dbService ?? GetIt.I<DatabaseService>();

  final DatabaseService _dbService;
  static const String _table = 'visit_plan_cache';

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Resuelve el uid del usuario actual para aislar el cache por usuario][obj: VisitPlanCacheStore._resolveUid]
  Future<String?> _resolveUid() async {
    final session = GetIt.I<AuthService>().currentSession;
    if (session != null && session.uid.isNotEmpty) return session.uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_uid');
    } catch (_) {
      return null;
    }
  }

  Future<void> savePlanRaw({required int planId, required String payload}) async {
    final uid = await _resolveUid();
    final db = await _dbService.database;
    await db.insert(
      _table,
      {
        'plan_id': planId,
        'payload': payload,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'user_id': uid,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> savePlan(VisitPlan plan) async {
    final payload = jsonEncode(plan.toJson());
    await savePlanRaw(planId: plan.id, payload: payload);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Filtra por user_id para que cada usuario solo vea su propio plan cacheado][obj: VisitPlanCacheStore.loadLatest]
  Future<VisitPlan?> loadLatest() async {
    final uid = await _resolveUid();
    if (uid == null || uid.isEmpty) return null;
    final db = await _dbService.database;
    final rows = await db.query(
      _table,
      where: 'user_id = ?',
      whereArgs: [uid],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = rows.first['payload'] as String?;
    if (payload == null || payload.isEmpty) return null;
    final json = jsonDecode(payload) as Map<String, dynamic>;
    return VisitPlan.fromJson(json);
  }

  Future<void> updateItemState({
    required int itemId,
    required VisitItemState newState,
  }) async {
    final plan = await loadLatest();
    if (plan == null) return;
    final updatedItems = plan.items
        .map((item) => item.id == itemId ? item.copyWith(state: newState) : item)
        .toList();
    final updatedPlan = plan.copyWith(items: updatedItems);
    await savePlan(updatedPlan);
  }
}
