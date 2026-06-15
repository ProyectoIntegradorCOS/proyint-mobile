import 'package:get_it/get_it.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/location_point.dart';
import '../models/cuestionario.dart';
import '../models/visit_plan.dart';
import '../services/auth_service.dart';
import 'secure_token_store.dart';
import '../services/telemetry_log_service.dart';
import '../utils/lima_time.dart';
import '../utils/logger.dart';
import '../models/user_profile.dart';

class ApiService {
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-12 09:05 UTC-5][desc: Aumenta timeout por latencias en emulador/backend][obj: ApiService ctor]
  ApiService({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 20);

  final http.Client _client;
  bool _userRegistered = false;
  String? _authToken;
  final Duration _timeout;

  Uri _buildUri(String path) {
    final base = Constants.apiBaseUrl;
    return Uri.parse('$base$path');
  }

  Future<void> updateAuthToken(String? token) async {
    token = SecureTokenStore.normalizeAuthToken(token);
    _authToken = token;
    if (token != null && token.isNotEmpty) {
      logInfo(
        'updateAuthToken: nuevo token seteado → _authToken + SecureTokenStore(auth_token)',
      );
    } else {
      logInfo(
        'updateAuthToken: token limpiado → _authToken=null + SecureTokenStore(auth_token)=null',
      );
    }
    try {
      await SecureTokenStore.writeAuthToken(token);
    } catch (_) {}
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Notifica al backend para evictar el token del cache Caffeine al hacer logout. Fire-and-forget: si falla no interrumpe el logout.][obj: ApiService.evictToken]
  Future<void> evictToken(String token) async {
    try {
      final uri = _buildUri('/auth/logout');
      await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 5));
      logInfo('evictToken: token evictado del cache del backend (logout)');
    } catch (e) {
      logWarn(
        'evictToken: no se pudo notificar al backend',
        details: e.toString(),
      );
    }
  }

  static Future<String?> loadSavedAuthToken() async {
    try {
      return await SecureTokenStore.readAuthToken();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _jsonHeaders() {
    final headers = {'Content-Type': 'application/json'};
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_authToken!}';
    }
    return headers;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Genera un traceId para correlacionar logs app↔backend][obj: ApiService._newTraceId]
  String _newTraceId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(12, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'trc_$hex';
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Preview seguro del token para diagnóstico (primeros 8 + últimos 6 chars)][obj: ApiService._tokenPreview]
  String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) return '(null)';
    if (token.length <= 16) return token;
    return '${token.substring(0, 8)}…${token.substring(token.length - 6)}';
  }

  static bool isSessionExpiredError(Object error) {
    return error is ApiException &&
        error.toString().contains('Sesión expirada');
  }

  // Workaround: reintenta renovando token ante 401 (ticket VIS-AUTH-RENEW)
  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() send, {
    String tag = '',
  }) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 10:18 UTC-5 (Lima)][desc: Valida/renueva token antes de cada request para evitar expiración silenciosa][obj: ApiService._sendWithRetry ensure token]
    final auth = GetIt.I<AuthService>();
    try {
      final ensured = await auth.ensureValidToken();
      if (ensured != null && ensured.isNotEmpty && ensured != _authToken) {
        _authToken = ensured;
        await updateAuthToken(ensured);
      }
    } catch (_) {}
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Log de diagnóstico para detectar token desactualizado en requests][obj: ApiService._sendWithRetry token diagnostic]
    final sessionToken = auth.currentSession?.token;
    final tokenMismatch =
        sessionToken != null &&
        _authToken != null &&
        _authToken != sessionToken;
    if (tokenMismatch) {
      logWarn(
        'TOKEN MISMATCH detectado${tag.isNotEmpty ? ' [$tag]' : ''}',
        details:
            'apiToken=${_tokenPreview(_authToken)} sessionToken=${_tokenPreview(sessionToken)}',
      );
    } else {
      logDebug(
        'request token${tag.isNotEmpty ? ' [$tag]' : ''}',
        details: 'preview=${_tokenPreview(_authToken)}',
      );
    }
    http.Response response = await send().timeout(_timeout);
    if (response.statusCode != 401) {
      return response;
    }
    // intento 1: renovar token
    if (await auth.renewToken()) {
      _authToken = auth.currentSession?.token;
      if (_authToken != null) {
        await updateAuthToken(_authToken);
      }
      response = await send().timeout(_timeout);
      if (response.statusCode != 401) return response;
    }
    // intento 2: reautenticación con credenciales recordadas
    if (await auth.attemptReauthIfRemembered()) {
      _authToken = auth.currentSession?.token;
      if (_authToken != null) {
        await updateAuthToken(_authToken);
      }
      response = await send().timeout(_timeout);
      if (response.statusCode != 401) return response;
    }
    // fallback: cerrar sesión local y enviar al login
    logWarn('401 persistente, forzando logout y redirigiendo a login');
    try {
      await auth.signOut();
    } catch (_) {}
    throw ApiException('Sesión expirada. Redirigiendo al login.');
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Obtiene perfil de usuario con caché local][obj: ApiService.fetchUserProfile]
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Permite forzar fetch de red para horario exacto (evita usar caché desactualizado)][obj: ApiService.fetchUserProfile forceNetwork]
  Future<UserProfile?> fetchUserProfile(
    String saaSubject, {
    bool forceNetwork = false,
  }) async {
    logDebug(
      "Entramos a fetchUserProfile y recibimos el saaSubject: " + saaSubject,
    );
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'user_profile_$saaSubject';

    logDebug("cacheKey: " + cacheKey);
    if (forceNetwork) {
      return _fetchAndCacheUserProfile(saaSubject, cacheKey);
    }
    // Intentar cargar de caché primero
    final cachedJson = prefs.getString(cacheKey);
    if (cachedJson != null) {
      try {
        final data = jsonDecode(cachedJson) as Map<String, dynamic>;
        // Opcional: Verificar antigüedad del caché si se guardara timestamp
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
      final response = await _sendWithRetry(
        () => _client.get(uri, headers: _jsonHeaders()),
      );
      if (response.statusCode == 200) {
        final body = response.body;
        final data = jsonDecode(body) as Map<String, dynamic>;
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Traza horario retornado por /users para diagnosticar desalineación de horario (caché vs backend)][obj: ApiService._fetchAndCacheUserProfile horario log]
        try {
          final hid = (data['horarioId'] as num?)?.toInt();
          final hname = data['horarioNombre']?.toString();
          logDebug(
            'Perfil /users recibido',
            details: 'uid=$saaSubject horarioId=$hid horarioNombre=$hname',
          );
        } catch (_) {}

        // Guardar en caché
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, body);

        return UserProfile.fromJson(data);
      }
      if (response.statusCode == 404) {
        return null;
      }
      throw ApiException(
        'Error obteniendo usuario (${response.statusCode}): ${response.body}',
      );
    } catch (e) {
      // Si falló la red y no teníamos caché, relanzamos.
      // Si teníamos caché, este método fue llamado en background y el error se perderá (lo cual está bien para swr)
      // Pero como este método también es el principal si no hay caché, debemos manejarlo.
      // Para simplificar, si es llamado desde el return del if(cached), el await no se espera.
      // Pero aquí lo estamos llamando y retornando.
      rethrow;
    }
  }

  Future<void> _refreshProfileCache(String saaSubject, String cacheKey) async {
    try {
      await _fetchAndCacheUserProfile(saaSubject, cacheKey);
    } catch (e) {
      logWarn(
        'No se pudo refrescar el perfil en background',
        details: e.toString(),
      );
    }
  }

  Future<List<EquipoOption>> fetchEquiposActivos() async {
    final uri = _buildUri('/equipo/lista-activa');
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        'Error obteniendo equipos (${response.statusCode}): ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = decoded['resultados'] as List<dynamic>? ?? [];
    return list
        .map((e) => EquipoOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<HorarioOption>> fetchHorarios() async {
    final uri = _buildUri('/horarios');
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        'Error obteniendo horarios (${response.statusCode}): ${response.body}',
      );
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => HorarioOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:25 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: ApiService.fetchCuestionarioActivo]
  Future<Cuestionario?> fetchCuestionarioActivo() async {
    final uri = _buildUri('/cuestionarios/activo');
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode == 204) {
      return null;
    }
    if (response.statusCode != 200) {
      throw ApiException(
        'Error obteniendo cuestionario (${response.statusCode}): ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Cuestionario.fromJson(data);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:25 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: ApiService.fetchPreguntasPorCuestionario]
  Future<List<Pregunta>> fetchPreguntasPorCuestionario(
    int idCuestionario,
  ) async {
    final uri = _buildUri('/preguntas/cuestionario/$idCuestionario');
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        'Error obteniendo preguntas (${response.statusCode}): ${response.body}',
      );
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => Pregunta.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:25 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: ApiService.registrarRespuestas]
  Future<void> registrarRespuestas(List<RespuestaPayload> respuestas) async {
    for (final respuesta in respuestas) {
      final uri = _buildUri('/respuestas');
      final response = await _sendWithRetry(
        () => _client.post(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode(respuesta.toJson()),
        ),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw ApiException(
          'Error guardando respuestas (${response.statusCode}): ${response.body}',
        );
      }
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:42 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: ApiService.fetchRespuestasCuestionario]
  Future<List<RespuestaPregunta>> fetchRespuestasCuestionario({
    required int idCuestionario,
    required int idPersona,
  }) async {
    final uri = _buildUri(
      '/respuestas/cuestionario/$idCuestionario',
    ).replace(queryParameters: {'idPersona': idPersona.toString()});
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        'Error obteniendo respuestas (${response.statusCode}): ${response.body}',
      );
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => RespuestaPregunta.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-22 09:23 UTC-5 (Lima)][desc: Obtiene respuestas por item de visita para mostrar solo lo atendido][obj: ApiService.fetchRespuestasPorItem]
  Future<List<RespuestaPregunta>> fetchRespuestasPorItem({
    required int idItem,
  }) async {
    final uri = _buildUri('/respuestas/visit-item/$idItem');
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        'Error obteniendo respuestas (${response.statusCode}): ${response.body}',
      );
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => RespuestaPregunta.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-23 11:51 UTC-5 (Lima)][desc: Envía métricas de la app móvil al backend][obj: ApiService.sendMetric]
  Future<void> sendMetric({
    required String action,
    required String screen,
    String status = 'success',
    int? durationMs,
    String? version,
  }) async {
    final payload = <String, dynamic>{
      'action': action,
      'screen': screen,
      'status': status,
    };
    if (durationMs != null) payload['durationMs'] = durationMs;
    if (version != null && version.isNotEmpty) payload['version'] = version;
    final uri = _buildUri('/metrics/mobile');
    try {
      await _sendWithRetry(
        () => _client.post(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode(payload),
        ),
      );
    } catch (_) {
      // Ignore metrics errors to avoid impacting UX
    }
  }

  Future<HorarioOption> fetchHorarioById(int id) async {
    final uri = _buildUri('/horarios/$id');
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return HorarioOption.fromJson(json);
    }
    throw ApiException(
      'Error obteniendo horario (${response.statusCode}): ${response.body}',
    );
  }

  Future<UserProfile> saveUserProfile({
    int? id,
    required String saaSubject,
    required String usuario,
    required String nombre,
    required int estado,
    required int horarioId,
    required int equipoId,
    String? email,
    required String usuarioSesion,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      'saaSubject': saaSubject,
      'usuario': usuario,
      'nombre': nombre,
      'estado': estado,
      'equipoId': equipoId,
      'horarioId': horarioId,
      'usuarioSesion': usuarioSesion,
    };
    if (email != null && email.isNotEmpty) {
      payload['email'] = email;
    }
    final response = await _sendWithRetry(() {
      return _client.post(
        _buildUri('/users'),
        headers: _jsonHeaders(),
        body: jsonEncode(payload),
      );
    });
    if (response.statusCode == 200 || response.statusCode == 201) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return UserProfile.fromJson(json);
    }
    throw ApiException(
      'Error guardando usuario (${response.statusCode}): ${response.body}',
    );
  }

  Future<void> sendLocation({
    required String firebaseUid,
    required LocationPoint point,
    int? batteryLevel,
    String? activityType,
  }) async {
    final startedAt = DateTime.now();
    final traceId = _newTraceId();
    logDebug(
      'Enviando ubicación al backend',
      details:
          'uid=$firebaseUid lat=${point.latitude} lng=${point.longitude} ts=${point.timestamp.toIso8601String()}',
    );
    logInfo(
      'API sendLocation -> POST /locations',
      details:
          'traceId=$traceId uid=$firebaseUid ts=${toLimaIsoString(point.timestamp)}',
    );
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Duplica traza en DEBUG porque en algunos dispositivos solo se ve [DEBUG] en consola Flutter][obj: ApiService.sendLocation trace debug]
    logDebug(
      'API sendLocation -> POST /locations',
      details:
          'traceId=$traceId uid=$firebaseUid ts=${toLimaIsoString(point.timestamp)}',
    );
    final payload = {
      'saaSubject': firebaseUid,
      'latitude': point.latitude,
      'longitude': point.longitude,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Envía timestamp en zona Lima (-05:00) para persistencia/reportes][obj: ApiService.sendLocation timestamp Lima]
      'timestamp': toLimaIsoString(point.timestamp),
      if (point.accuracy != null) 'accuracy': point.accuracy,
      if (point.altitude != null) 'altitude': point.altitude,
      if (point.speed != null) 'speed': point.speed,
      if (point.heading != null) 'heading': point.heading,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
      if (activityType != null) 'activityType': activityType,
    };

    final response = await _sendWithRetry(() {
      return _client.post(
        _buildUri('/locations'),
        headers: {..._jsonHeaders(), 'X-Trace-Id': traceId},
        body: jsonEncode(payload),
      );
    });

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:30 UTC-5 (Lima)][desc: Corrige lógica de retorno en sendLocation][obj: ApiService.sendLocation]
    if (response.statusCode == 200 || response.statusCode == 201) {
      logInfo(
        'API sendLocation OK',
        details: 'traceId=$traceId status=${response.statusCode}',
      );
      logDebug('Ubicación enviada correctamente');
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-23 12:01 UTC-5 (Lima)][desc: Registra métrica de geolocalización exitosa][obj: ApiService.sendLocation metric]
      await sendMetric(
        action: 'ubicacion_envio',
        screen: 'geolocalizacion',
        status: 'success',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      return;
    }

    logError(
      'API sendLocation FAIL',
      error:
          'traceId=$traceId status=${response.statusCode} body=${response.body}',
    );
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-23 12:01 UTC-5 (Lima)][desc: Registra error de geolocalización al enviar ubicación][obj: ApiService.sendLocation metric]
    await sendMetric(
      action: 'ubicacion_envio',
      screen: 'geolocalizacion',
      status: 'error',
    );
    throw ApiException(
      'Error enviando ubicación (${response.statusCode}): ${response.body}',
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Envía lote de ubicaciones al backend][obj: ApiService.sendLocationBatch]
  Future<void> sendLocationBatch(List<Map<String, dynamic>> locations) async {
    if (locations.isEmpty) return;

    final startedAt = DateTime.now();
    final traceId = _newTraceId();
    logDebug('Enviando batch de ${locations.length} ubicaciones');
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Normaliza payload batch: elimina campos locales y tipa batteryLevel como int para backend][obj: ApiService.sendLocationBatch]
    final normalizedLocations = locations.map((m) {
      final out = Map<String, dynamic>.from(m);
      out.remove('id'); // campo local SQLite
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: No enviar campos internos de retención/purga al backend][obj: ApiService.sendLocationBatch remove timestamp_epoch_ms]
      out.remove(
        'timestamp_epoch_ms',
      ); // campo local SQLite para retención/purga
      final bl = out['batteryLevel'];
      if (bl is num) {
        out['batteryLevel'] = bl.round(); // backend espera Integer
      }
      return out;
    }).toList();
    final payload = {'locations': normalizedLocations};

    final firstTs = normalizedLocations.first['timestamp']?.toString();
    final lastTs = normalizedLocations.last['timestamp']?.toString();
    logInfo(
      'API sendLocationBatch -> POST /locations/batch',
      details:
          'traceId=$traceId count=${normalizedLocations.length} firstTs=$firstTs lastTs=$lastTs',
    );
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Duplica traza en DEBUG porque en algunos dispositivos solo se ve [DEBUG] en consola Flutter][obj: ApiService.sendLocationBatch trace debug]
    logDebug(
      'API sendLocationBatch -> POST /locations/batch',
      details:
          'traceId=$traceId count=${normalizedLocations.length} firstTs=$firstTs lastTs=$lastTs',
    );

    final response = await _sendWithRetry(() {
      return _client.post(
        _buildUri('/locations/batch'),
        headers: {..._jsonHeaders(), 'X-Trace-Id': traceId},
        body: jsonEncode(payload),
      );
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      logInfo(
        'API sendLocationBatch OK',
        details:
            'traceId=$traceId status=${response.statusCode} body=${response.body}',
      );
      logDebug('Batch enviado correctamente');
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-23 12:01 UTC-5 (Lima)][desc: Registra métrica de geolocalización batch exitosa][obj: ApiService.sendLocationBatch metric]
      await sendMetric(
        action: 'ubicacion_envio_batch',
        screen: 'geolocalizacion',
        status: 'success',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      return;
    }

    logError(
      'API sendLocationBatch FAIL',
      error:
          'traceId=$traceId status=${response.statusCode} body=${response.body}',
    );
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-23 12:01 UTC-5 (Lima)][desc: Registra error de geolocalización al enviar batch][obj: ApiService.sendLocationBatch metric]
    await sendMetric(
      action: 'ubicacion_envio_batch',
      screen: 'geolocalizacion',
      status: 'error',
    );
    throw ApiException(
      'Error enviando batch (${response.statusCode}): ${response.body}',
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:30 UTC-5 (Lima)][desc: Separa método de distancia diaria correctamente][obj: ApiService.fetchDailyDistance]
  Future<double> fetchDailyDistance({
    required String firebaseUid,
    required DateTime date,
  }) async {
    logDebug(
      'Consultando distancia diaria',
      details: 'uid=$firebaseUid date=${date.toIso8601String()}',
    );
    final uri = _buildUri(
      '/locations/distance?saaSubject=$firebaseUid&date=${date.toIso8601String().split('T').first}',
    );
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        'Error obteniendo distancia (${response.statusCode}): ${response.body}',
      );
    }
    logDebug('Distancia obtenida: ${response.body}');
    return double.tryParse(response.body) ?? 0.0;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:45 UTC-5 (Lima)][desc: Agrega método para obtener historial de ubicaciones por rango de fechas][obj: ApiService.fetchLocationHistory]
  Future<LocationHistory> fetchLocationHistory({
    required String firebaseUid,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    logDebug(
      'Consultando historial de ubicaciones',
      details:
          'uid=$firebaseUid start=${startDate.toIso8601String()} end=${endDate.toIso8601String()}',
    );
    final uri = _buildUri(
      '/locations/history?saaSubject=$firebaseUid&start=${startDate.toUtc().toIso8601String()}&end=${endDate.toUtc().toIso8601String()}',
    );
    final response = await _sendWithRetry(
      () => _client.get(uri, headers: _jsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        'Error obteniendo historial (${response.statusCode}): ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final pointsList =
        (json['points'] as List<dynamic>?)
            ?.map((p) => LocationPoint.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];
    final totalKm = (json['totalDistanceKm'] as num?)?.toDouble() ?? 0.0;

    logDebug('Historial obtenido: ${pointsList.length} puntos, $totalKm km');
    return LocationHistory(
      points: pointsList,
      totalDistanceKm: totalKm,
      start: startDate,
      end: endDate,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:45 UTC-5 (Lima)][desc: Alias de fetchLocationHistory para compatibilidad][obj: ApiService.fetchHistory]
  Future<LocationHistory> fetchHistory({
    required String firebaseUid,
    required DateTime start,
    required DateTime end,
  }) async {
    return fetchLocationHistory(
      firebaseUid: firebaseUid,
      startDate: start,
      endDate: end,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-12 09:30 UTC-5][desc: Obtiene plan con reintento y logging detallado][obj: ApiService.fetchVisitPlanForMe]
  Future<VisitPlan> fetchVisitPlanForMe() async {
    final uri = _buildUri('/visit-plans/mine');
    logDebug(
      'fetchVisitPlanForMe inicio',
      details:
          'url=$uri token=${_authToken != null ? 'set(${_authToken!.length} chars)' : 'empty'}',
    );
    Future<http.Response> _doGet() => _client.get(uri, headers: _jsonHeaders());

    http.Response response;
    try {
      response = await _sendWithRetry(_doGet);
    } catch (e) {
      logError('fetchVisitPlanForMe fallo red/401', error: e);
      if (isSessionExpiredError(e)) {
        rethrow;
      }
      // Reintento ligero tras un pequeño delay
      await Future<void>.delayed(const Duration(seconds: 1));
      response = await _client
          .get(uri, headers: _jsonHeaders())
          .timeout(_timeout);
    }

    logDebug(
      'fetchVisitPlanForMe respuesta',
      details:
          'status=${response.statusCode} len=${response.body.length} bodyPreview=${response.body.length > 120 ? response.body.substring(0, 120) + '…' : response.body}',
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitPlan.fromJson(json);
    }
    if (response.statusCode == 401) {
      try {
        await GetIt.I<AuthService>().signOut();
      } catch (_) {}
      throw ApiException('Sesión expirada. Redirigiendo al login.');
    }
    if (response.statusCode == 404) {
      throw ApiException('No tienes un plan de visitas asignado.');
    }
    throw ApiException(
      'Error obteniendo plan (${response.statusCode}): ${response.body}',
    );
  }

  Future<VisitPlan> reorderVisitItems({
    required int planId,
    required List<int> itemIds,
  }) async {
    final uri = _buildUri('/visit-plans/$planId/items/reorder');
    final response = await _sendWithRetry(() {
      return _client.patch(
        uri,
        headers: _jsonHeaders(),
        body: jsonEncode({'itemIds': itemIds}),
      );
    });
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitPlan.fromJson(json);
    }
    throw ApiException(
      'Error reordenando visitas (${response.statusCode}): ${response.body}',
    );
  }

  Future<VisitItem> updateVisitState({
    required int itemId,
    required VisitItemState newState,
    double? startLatitude,
    double? startLongitude,
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 11:27 UTC-5 (Lima)][desc: Envía coordenadas del evento de cambio de estado][obj: ApiService.updateVisitState event coords]
    double? eventLatitude,
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 11:27 UTC-5 (Lima)][desc: Envía coordenadas del evento de cambio de estado][obj: ApiService.updateVisitState event coords]
    double? eventLongitude,
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Fecha/hora real del evento en el dispositivo para preservar timestamps offline][obj: ApiService.updateVisitState occurredAt]
    DateTime? occurredAt,
    required String source,
  }) async {
    final uri = _buildUri('/visit-plans/items/$itemId/state');
    final payload = {
      'newState': newState.apiValue,
      if (startLatitude != null) 'startLatitude': startLatitude,
      if (startLongitude != null) 'startLongitude': startLongitude,
      if (eventLatitude != null) 'eventLatitude': eventLatitude,
      if (eventLongitude != null) 'eventLongitude': eventLongitude,
      if (occurredAt != null) 'occurredAt': toLimaIsoString(occurredAt),
    };
    try {
      await GetIt.I<TelemetryLogService>().log(
        'updateVisitState: origen=$source itemId=$itemId payload=$payload',
      );
    } catch (_) {}
    final response = await _sendWithRetry(() {
      return _client.patch(
        uri,
        headers: _jsonHeaders(),
        body: jsonEncode(payload),
      );
    });
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitItem.fromJson(json);
    }
    throw ApiException(
      'No se pudo actualizar el estado (${response.statusCode}): ${response.body}',
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-09 11:02 UTC-5 (Lima)][desc: Verifica disponibilidad del backend antes de cambios críticos de estado][obj: ApiService.checkBackendAvailable]
  Future<bool> checkBackendAvailable({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final resp = await _client
          .get(_buildUri('/health/db'), headers: _jsonHeaders())
          .timeout(timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<VisitItem> completeVisit({
    required int itemId,
    bool? complex,
    bool? foundProblem,
    String? problemNote,
    String? otherInfo,
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 11:27 UTC-5 (Lima)][desc: Envía coordenadas del cierre de visita][obj: ApiService.completeVisit event coords]
    double? eventLatitude,
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 11:27 UTC-5 (Lima)][desc: Envía coordenadas del cierre de visita][obj: ApiService.completeVisit event coords]
    double? eventLongitude,
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Fecha/hora real del evento en el dispositivo para preservar timestamps offline][obj: ApiService.completeVisit occurredAt]
    DateTime? occurredAt,
  }) async {
    final uri = _buildUri('/visit-plans/items/$itemId/complete');
    final response = await _sendWithRetry(() {
      return _client.post(
        uri,
        headers: _jsonHeaders(),
        body: jsonEncode({
          'complex': complex,
          'foundProblem': foundProblem,
          if (problemNote != null && problemNote.isNotEmpty)
            'problemNote': problemNote,
          if (otherInfo != null && otherInfo.isNotEmpty) 'otherInfo': otherInfo,
          if (eventLatitude != null) 'eventLatitude': eventLatitude,
          if (eventLongitude != null) 'eventLongitude': eventLongitude,
          if (occurredAt != null) 'occurredAt': toLimaIsoString(occurredAt),
        }),
      );
    });
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitItem.fromJson(json);
    }
    throw ApiException(
      'No se pudo completar la visita (${response.statusCode}): ${response.body}',
    );
  }

  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => '$message';
}

class HistoryResponse {
  HistoryResponse({
    required this.firebaseUid,
    required this.start,
    required this.end,
    required this.points,
    required this.totalDistanceKm,
  });

  final String firebaseUid;
  final DateTime start;
  final DateTime end;
  final List<LocationPoint> points;
  final double totalDistanceKm;

  factory HistoryResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['points'] as List<dynamic>? ?? [])
        .map((item) => _pointFromJson(item as Map<String, dynamic>))
        .toList();
    final uidValue =
        json['saaSubject'] as String? ?? json['firebaseUid'] as String? ?? '';
    return HistoryResponse(
      firebaseUid: uidValue,
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      points: list,
      totalDistanceKm: (json['totalDistanceKm'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static LocationPoint _pointFromJson(Map<String, dynamic> json) {
    return LocationPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
    );
  }
}
