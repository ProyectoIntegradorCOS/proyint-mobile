import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AuditService {
  AuditService._();
  static final instance = AuditService._();

  static const _key = 'audit_events';

  Future<void> logEvent(String type, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    final event = {
      'type': type,
      'timestamp': DateTime.now().toIso8601String(),
      'data': data,
    };
    list.add(jsonEncode(event));
    await prefs.setStringList(_key, list);
  }

  Future<List<Map<String, dynamic>>> getEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

