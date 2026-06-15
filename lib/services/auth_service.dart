// import 'package:firebase_auth/firebase_auth.dart'; // Comentado: se migra a SAA
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import '../config/constants.dart';
import 'secure_token_store.dart';

// Sesión de usuario basada en SAA
class UserSession {
  UserSession({
    required this.uid,
    required this.usuario,
    required this.token,
    required this.nombre,
    this.email,
    this.permisos = const <String>[],
  });

  final String uid; // Claim `sub` del JWT SAA
  final String usuario; // Claim `Usuario` o input
  final String token; // JWT SAA
  final String nombre; // Claim `Nombre`
  final String? email; // Puede provenir de claims o derivarse
  final List<String> permisos; // PerfilPermiso del JWT
}

class AuthService {
  AuthService();
  // Future<void> register({required String email, required String password}) async {
  //   await _auth.createUserWithEmailAndPassword(email: email, password: password);
  // }
  // Future<void> signOut() => _auth.signOut();
  // Future<String?> getIdToken() async => _auth.currentUser?.getIdToken();

  void _ensureBackendConfigured() {
    if (Constants.apiBaseUrl.isEmpty) {
      throw Exception('Falta configurar API_BASE_URL/URL_BACKEND');
    }
  }

  String? _normalizeToken(String? token) {
    return SecureTokenStore.normalizeAuthToken(token);
  }

  final StreamController<UserSession?> _controller =
      StreamController<UserSession?>.broadcast();

  UserSession? _currentSession;

  // Importante: emitimos el estado actual primero para evitar pantallas esperando
  // cuando el listener se suscribe después de restoreSession().
  Stream<UserSession?> get authStateChanges async* {
    yield _currentSession;
    yield* _controller.stream;
  }

  UserSession? get currentSession => _currentSession;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 12:13 UTC-5 (Lima)][desc: Limpia la traza del último flush nativo para no arrastrar errores históricos entre sesiones][obj: AuthService._resetBgFlushDiagnostics]
  Future<void> _resetBgFlushDiagnostics(SharedPreferences prefs) async {
    await prefs.remove('bg_flush_last_at');
    await prefs.remove('bg_flush_last_status');
  }

  Future<void> restoreSession() async {
    logDebug('restoreSession: iniciando carga desde SharedPreferences');
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _normalizeToken(await SecureTokenStore.readAuthToken());
      final usuario = prefs.getString('auth_usuario');
      logDebug(
        'restoreSession: prefs',
        details:
            'token=${token != null ? token.length : 0} chars usuario=$usuario',
      );
      if (token != null &&
          token.isNotEmpty &&
          usuario != null &&
          usuario.isNotEmpty) {
        final claims = _decodeJwtClaims(token);
        final uid = _readString(claims, 'sub') ?? usuario;
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Persiste auth_uid para uso de scheduler Android en background][obj: AuthService.restoreSession]
        try {
          await prefs.setString('auth_uid', uid);
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Persiste tracking_uid para permitir tracking por horario incluso sin sesión][obj: AuthService.restoreSession tracking_uid]
          await prefs.setString('tracking_uid', uid);
        } catch (_) {}
        final nombreClaim = _readString(claims, 'Nombre');
        final storedNombre = prefs.getString('auth_nombre');
        final email = _deriveEmail(claims: claims, usuario: usuario);
        final permisos = _extractPermisos(claims);
        _currentSession = UserSession(
          uid: uid,
          usuario: usuario,
          token: token,
          nombre: nombreClaim ?? storedNombre ?? usuario,
          email: email,
          permisos: permisos,
        );
        _controller.add(_currentSession);
      } else {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 12:13 UTC-5 (Lima)][desc: Si no hay sesión restaurable, limpia diagnóstico nativo viejo para no mostrar errores obsoletos][obj: AuthService.restoreSession bg flush reset]
        await _resetBgFlushDiagnostics(prefs);
        _controller.add(null);
      }
    } catch (e, st) {
      logError('Error restaurando sesión', error: e, stackTrace: st);
      _controller.add(null);
    }
  }

  Future<void> signInSaa({
    required String usuario,
    required String contrasena,
    String codigoSistema = '641', // Hardcode por ahora
    bool rememberCredenciales = false,
  }) async {
    logDebug(
      'Autenticando contra backend',
      details: 'usuario=$usuario sistema=$codigoSistema',
    );
    logDebug(
      'signInSaa inicio',
      details: 'payload usuario=$usuario codigo=$codigoSistema',
    );
    final payload = {
      'usuario': usuario,
      'contrasena': contrasena,
      'codigoSistema': codigoSistema,
    };
    _ensureBackendConfigured();
    logDebug('Auth backend', details: 'url=${_backendAuthUrl()}');
    final response = await _postAuthToken(_backendAuthUrl(), payload);

    logDebug(
      'Respuesta backend auth',
      details: 'status=${response.statusCode} len=${response.body.length}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Error backend auth (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = _normalizeToken(data['token'] as String?);
    if (token == null || token.isEmpty) {
      throw Exception('Respuesta backend sin token');
    }

    final claims = _decodeJwtClaims(token);
    final uid = _readString(claims, 'sub') ?? usuario;
    final usuarioClaim = _readString(claims, 'Usuario') ?? usuario;
    final nombreClaim = _readString(claims, 'Nombre') ?? usuarioClaim;
    final email = _deriveEmail(claims: claims, usuario: usuarioClaim);
    final permisos = _extractPermisos(claims);

    try {
      final prefs = await SharedPreferences.getInstance();
      await SecureTokenStore.writeAuthToken(token);
      await prefs.setString('auth_usuario', usuarioClaim);
      await prefs.setString('auth_nombre', nombreClaim);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Persiste auth_uid para scheduling nativo (AlarmManager) y refresh de horario][obj: AuthService.signInSaa]
      await prefs.setString('auth_uid', uid);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Persiste tracking_uid para tracking por horario aunque cierre sesión][obj: AuthService.signInSaa tracking_uid]
      await prefs.setString('tracking_uid', uid);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 12:13 UTC-5 (Lima)][desc: Resetea diagnóstico del último flush nativo al iniciar sesión para no heredar errores previos][obj: AuthService.signInSaa bg flush reset]
      await _resetBgFlushDiagnostics(prefs);
      await prefs.setBool('remember_creds', rememberCredenciales);
      if (rememberCredenciales) {
        await prefs.setString('remembered_usuario', usuario);
      } else {
        await prefs.remove('remembered_usuario');
      }
    } catch (_) {}

    _currentSession = UserSession(
      uid: uid,
      usuario: usuarioClaim,
      token: token,
      nombre: nombreClaim,
      email: email,
      permisos: permisos,
    );
    _controller.add(_currentSession);
    logInfo(
      'signInSaa: token seteado → _currentSession.token + SecureTokenStore(auth_token) + SharedPreferences(auth_uid=$uid, auth_usuario=$usuarioClaim)',
    );
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Evita imprimir token SAA completo en logs (solo longitud)][obj: AuthService.signInSaa token log]
    logDebug('Token SAA obtenido', details: 'len=${token.length}');
    logDebug('Permisos SAA (decodificados)', details: permisos.join(', '));
    logDebug('Claims decodificados', details: claims.toString());
    if (permisos.isNotEmpty) {
      logDebug(
        'Permisos SAA',
        details: '${permisos.length}: ${permisos.take(5).join(', ')}',
      );
    } else {
      logDebug('Permisos SAA vacíos o no presentes');
    }
  }

  Future<void> signOut() async {
    logDebug('signOut llamado', details: 'usuario=${_currentSession?.usuario}');
    await _clearLocalSession();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-09 11:05 UTC-5 (Lima)][desc: Envía request de token con timeout controlado][obj: AuthService._postAuthToken]
  Future<http.Response> _postAuthToken(
    String url,
    Map<String, dynamic> payload,
  ) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-09 11:08 UTC-5 (Lima)][desc: Loguea tiempo de respuesta y desactiva timeout en login para pruebas][obj: AuthService._postAuthToken timing]
    final sw = Stopwatch()..start();
    try {
      return await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } finally {
      sw.stop();
      logDebug(
        'Auth token response time',
        details: 'url=$url ms=${sw.elapsedMilliseconds}',
      );
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-09 11:05 UTC-5 (Lima)][desc: Construye URL backend para autenticación SAA vía API propia][obj: AuthService._backendAuthUrl]
  String _backendAuthUrl() {
    final base = Constants.apiBaseUrl;
    return '$base/auth/token';
  }

  String _backendLogoutUrl() {
    final base = Constants.apiBaseUrl;
    return '$base/auth/logout';
  }

  String _backendRenewUrl() {
    final base = Constants.apiBaseUrl;
    return '$base/auth/renew';
  }

  // Cierra sesión vía backend enviando el token en Authorization.
  Future<LogoutResult> signOutSaa() async {
    logDebug('signOutSaa llamado');
    final token = _currentSession?.token ?? await _loadSavedToken();
    if (token == null || token.isEmpty) {
      await _clearLocalSession();
      return LogoutResult(
        resultado: '3',
        mensaje: 'El token debe ser distinto de vacío',
        success: false,
      );
    }
    try {
      _ensureBackendConfigured();
      logDebug(
        'Cerrando sesión vía backend',
        details: 'url=${_backendLogoutUrl()}',
      );
      final resp = await http
          .post(
            Uri.parse(_backendLogoutUrl()),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 09:57 UTC-5 (Lima)][desc: Loguea metadatos de respuesta no-2xx sin exponer body][obj: AuthService.signOutSaa]
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        logWarn(
          'Cierre backend auth fallo',
          details:
              'status=${resp.statusCode} len=${resp.body.length} content-type=${resp.headers['content-type'] ?? ''}',
        );
        return LogoutResult(resultado: '4', mensaje: 'ERROR', success: false);
      }
      String resultado = '';
      String mensaje = '';
      try {
        final json = jsonDecode(resp.body);
        if (json is Map<String, dynamic>) {
          final r = json['resultado'];
          final m = json['mensaje'];
          resultado = r?.toString() ?? '';
          mensaje = m?.toString() ?? '';
        } else {
          mensaje = 'Respuesta inesperada del backend';
        }
      } catch (_) {
        mensaje = 'No se pudo parsear la respuesta del backend';
      }
      final success = resultado == '1';
      if (success) {
        logDebug('Sesión cerrada vía backend: $mensaje');
      } else {
        logError(
          'Cierre backend auth no exitoso',
          error: 'resultado=$resultado mensaje=$mensaje',
        );
      }
      return LogoutResult(
        resultado: resultado.isEmpty ? '4' : resultado,
        mensaje: mensaje,
        success: success,
      );
    } catch (e, st) {
      logError('Excepción cerrando sesión SAA', error: e, stackTrace: st);
      return LogoutResult(resultado: '4', mensaje: 'ERROR', success: false);
    } finally {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 09:57 UTC-5 (Lima)][desc: Evita recursión; limpieza local separada tras cierre remoto][obj: AuthService.signOutSaa cleanup]
      await _clearLocalSession();
    }
  }

  Future<String?> _loadSavedToken() async {
    try {
      return await SecureTokenStore.readAuthToken();
    } catch (_) {
      return null;
    }
  }

  Future<String?> getIdToken() async => _currentSession?.token;

  // Utilidades
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 10:18 UTC-5 (Lima)][desc: Renueva token solo si está por expirar o expirado (según claim exp)][obj: AuthService.ensureValidToken]
  Future<String?> ensureValidToken({
    Duration minTtl = const Duration(minutes: 5),
  }) async {
    final token = _currentSession?.token ?? await _loadSavedToken();
    if (token == null || token.isEmpty) return null;
    final claims = _decodeJwtClaims(token);
    final exp = _readInt(claims, 'exp');
    if (exp == null) return token;
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final ttl = exp - nowSec;
    if (ttl <= 0 || ttl <= minTtl.inSeconds) {
      await renewToken();
      return _currentSession?.token ?? await _loadSavedToken();
    }
    return token;
  }

  Future<void> _clearLocalSession() async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 09:57 UTC-5 (Lima)][desc: Extrae limpieza local para reutilizarla sin cerrar sesión remota][obj: AuthService._clearLocalSession]
    try {
      final prefs = await SharedPreferences.getInstance();
      await SecureTokenStore.writeAuthToken(null);
      await prefs.remove('auth_usuario');
      await prefs.remove('auth_nombre');
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Limpia auth_uid en logout para evitar scheduling con usuario anterior][obj: AuthService.signOut]
      await prefs.remove('auth_uid');
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 12:13 UTC-5 (Lima)][desc: Limpia diagnóstico del último flush nativo al cerrar sesión para evitar que el chip muestre estado viejo][obj: AuthService._clearLocalSession bg flush reset]
      await _resetBgFlushDiagnostics(prefs);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Mantiene tracking_uid para permitir tracking por horario aunque haya logout real][obj: AuthService.signOut keep tracking_uid]
      // No limpiamos credenciales si el usuario optó por recordarlas (se descartan en signInSaa cuando no las quiere)
    } catch (_) {}
    logInfo(
      '_clearLocalSession: token eliminado → _currentSession=null + SecureTokenStore(auth_token)=null + SharedPreferences(auth_uid, auth_usuario, auth_nombre) borrados',
    );
    _currentSession = null;
    _controller.add(null);
  }

  Map<String, dynamic> _decodeJwtClaims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return <String, dynamic>{};
    try {
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final bytes = base64Url.decode(normalized);
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return map;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String? _readString(Map map, String key) {
    final v = map[key];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  int? _readInt(Map map, String key) {
    final v = map[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  String _domainFromUsuario(String usuario) {
    // Dominio de prueba; ajustar más adelante
    return '${usuario.toLowerCase()}@saa.local';
  }

  String? _deriveEmail({
    required Map<String, dynamic> claims,
    required String usuario,
  }) {
    final email = _readString(claims, 'email') ?? _readString(claims, 'Email');
    return email ?? _domainFromUsuario(usuario);
  }

  List<String> _extractPermisos(Map<String, dynamic> claims) {
    final raw = claims['PerfilPermiso'];
    if (raw is! List) return const <String>[];

    final out = <String>[];
    for (final perfil in raw) {
      if (perfil is! Map) continue;
      final arr = perfil['arrPermisos'];
      if (arr is! List) continue;
      for (final perm in arr) {
        if (perm is! Map) continue;
        final noAccion = _readString(perm, 'noAccion');
        final idPermiso = _readString(perm, 'idPermiso');
        final noPermiso = _readString(perm, 'noPermiso');
        if (noAccion != null && noAccion.isNotEmpty) out.add(noAccion);
        if (idPermiso != null && idPermiso.isNotEmpty) out.add(idPermiso);
        if (noPermiso != null && noPermiso.isNotEmpty) out.add(noPermiso);
      }
    }

    // Deduplicar conservando orden
    final seen = <String>{};
    final dedup = <String>[];
    for (final s in out) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) dedup.add(t);
    }
    return dedup;
  }

  Future<bool> attemptReauthIfRemembered() async {
    // Preferimos renovacion de token; no reintentamos con credenciales recordadas
    return false;
  }

  Future<bool> renewToken() async {
    final token = _normalizeToken(
      _currentSession?.token ?? await _loadSavedToken(),
    );
    if (token == null || token.isEmpty) return false;
    try {
      _ensureBackendConfigured();
      final resp = await http
          .post(
            Uri.parse(_backendRenewUrl()),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 09:57 UTC-5 (Lima)][desc: Valida status y content-type antes de parsear JSON en renovación][obj: AuthService.renewToken]
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        logWarn(
          'Renovacion token fallo',
          details:
              'status=${resp.statusCode} len=${resp.body.length} content-type=${resp.headers['content-type'] ?? ''}',
        );
        return false;
      }
      final contentType = resp.headers['content-type'] ?? '';
      if (!contentType.contains('application/json')) {
        logWarn('Renovacion token no devolvió JSON', details: contentType);
        return false;
      }
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) {
        final newToken = _normalizeToken(data['token'] as String?);
        if (newToken != null && newToken.isNotEmpty) {
          final claims = _decodeJwtClaims(newToken);
          final uid = _readString(claims, 'sub') ?? _currentSession?.uid;
          final usuario =
              _readString(claims, 'Usuario') ?? _currentSession?.usuario;
          final nombre = _readString(claims, 'Nombre') ?? usuario ?? uid;
          final email = _deriveEmail(claims: claims, usuario: usuario ?? '');
          final permisos = _extractPermisos(claims);
          final session = UserSession(
            uid: uid ?? '',
            usuario: usuario ?? '',
            token: newToken,
            nombre: nombre ?? '',
            email: email,
            permisos: permisos,
          );
          _currentSession = session;
          _controller.add(session);
          final prefs = await SharedPreferences.getInstance();
          await SecureTokenStore.writeAuthToken(newToken);
          if (usuario != null) await prefs.setString('auth_usuario', usuario);
          if (nombre != null) await prefs.setString('auth_nombre', nombre);
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Actualiza auth_uid al renovar token para background scheduler][obj: AuthService.renewToken]
          if (uid != null) await prefs.setString('auth_uid', uid);
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Mantiene tracking_uid sincronizado al renovar token][obj: AuthService.renewToken tracking_uid]
          if (uid != null) await prefs.setString('tracking_uid', uid);
          logDebug('Token renovado exitosamente');
          return true;
        }
        final resultado = data['resultado']?.toString();
        logWarn('Renovacion token no entregó nuevo token', details: resultado);
        return false;
      }
      return false;
    } catch (e, st) {
      logError('Error renovando token', error: e, stackTrace: st);
      return false;
    }
  }
}

class LogoutResult {
  LogoutResult({
    required this.resultado,
    required this.mensaje,
    required this.success,
  });
  final String resultado; // "1".."6"
  final String mensaje;
  final bool success;
}
