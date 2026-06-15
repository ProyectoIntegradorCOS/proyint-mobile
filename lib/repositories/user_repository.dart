import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../config/constants.dart';
import '../models/user_profile.dart';
import '../utils/logger.dart';

class UserRepository {
  final Future<http.Response> Function(Future<http.Response> Function()) sendWithRetry;
  final Map<String, String> Function() getJsonHeaders;

  UserRepository({
    required this.sendWithRetry,
    required this.getJsonHeaders,
  });

  Uri _buildUri(String path) {
    return Uri.parse('${Constants.apiBaseUrl}$path');
  }

  Future<UserProfile?> fetchUserProfile(
    String saaSubject, {
    bool forceNetwork = false,
  }) async {
    logDebug("Entramos a fetchUserProfile y recibimos el saaSubject: $saaSubject");
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'user_profile_$saaSubject';

    logDebug("cacheKey: $cacheKey");
    if (forceNetwork) {
      return _fetchAndCacheUserProfile(saaSubject, cacheKey);
    }
    
    // Intentar cargar de caché primero
    final cachedJson = prefs.getString(cacheKey);
    if (cachedJson != null) {
      try {
        final data = jsonDecode(cachedJson) as Map<String, dynamic>;
        logDebug('Perfil de usuario cargado de caché local');
        // Lanzamos la petición en background para actualizar si hay red (stale-while-revalidate)
        unawaited(_refreshProfileCache(saaSubject, cacheKey));
        return UserProfile.fromJson(data);
      } catch (_) {
        prefs.remove(cacheKey);
      }
    }

    return _fetchAndCacheUserProfile(saaSubject, cacheKey);
  }

  Future<UserProfile?> _fetchAndCacheUserProfile(
    String saaSubject,
    String cacheKey,
  ) async {
    final uri = _buildUri('/users/$saaSubject');
    try {
      final response = await sendWithRetry(
        () => http.get(uri, headers: getJsonHeaders()),
      );
      if (response.statusCode == 200) {
        final body = response.body;
        final data = jsonDecode(body) as Map<String, dynamic>;
        try {
          final hid = (data['horarioId'] as num?)?.toInt();
          final hname = data['horarioNombre']?.toString();
          logDebug('Perfil /users recibido', details: 'uid=$saaSubject horarioId=$hid horarioNombre=$hname');
        } catch (_) {}

        // Guardar en caché
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, body);

        return UserProfile.fromJson(data);
      }
      if (response.statusCode == 404) {
        return null;
      }
      throw Exception('Error obteniendo usuario (${response.statusCode}): ${response.body}');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _refreshProfileCache(String saaSubject, String cacheKey) async {
    try {
      await _fetchAndCacheUserProfile(saaSubject, cacheKey);
    } catch (e) {
      logWarn('No se pudo refrescar el perfil en background', details: e.toString());
    }
  }

  Future<List<EquipoOption>> fetchEquiposActivos() async {
    final uri = _buildUri('/equipo/lista-activa');
    final response = await sendWithRetry(
      () => http.get(uri, headers: getJsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw Exception('Error obteniendo equipos (${response.statusCode}): ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = decoded['resultados'] as List<dynamic>? ?? [];
    return list.map((e) => EquipoOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<HorarioOption>> fetchHorarios() async {
    final uri = _buildUri('/horarios');
    final response = await sendWithRetry(
      () => http.get(uri, headers: getJsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw Exception('Error obteniendo horarios (${response.statusCode}): ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => HorarioOption.fromJson(e as Map<String, dynamic>)).toList();
  }
}
