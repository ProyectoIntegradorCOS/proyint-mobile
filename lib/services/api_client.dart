import 'package:get_it/get_it.dart';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import '../utils/logger.dart';
import 'secure_token_store.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, Duration? timeout, AuthService? authService})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 20),
        _authService = authService;

  final http.Client _client;
  final Duration _timeout;
  final AuthService? _authService;
  String? _authToken;

  http.Client get httpClient => _client;
  Duration get timeout => _timeout;

  Future<void> updateAuthToken(String? token) async {
    _authToken = token;
    try {
      await SecureTokenStore.writeAuthToken(token);
    } catch (_) {}
  }

  static Future<String?> loadSavedAuthToken() async {
    try {
      return await SecureTokenStore.readAuthToken();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> getJsonHeaders() {
    final headers = {'Content-Type': 'application/json'};
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    headers['X-Trace-Id'] = getNewTraceId();
    return headers;
  }

  String getNewTraceId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(12, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'trc_$hex';
  }

  /// Ejecuta una petición HTTP e incorpora lógica de reintento en caso de token expirado (HTTP 401).
  Future<http.Response> sendWithRetry(Future<http.Response> Function() send) async {
    final auth = _authService ?? GetIt.I<AuthService>();
    try {
      final ensured = await auth.ensureValidToken();
      if (ensured != null && ensured.isNotEmpty && ensured != _authToken) {
        _authToken = ensured;
        await updateAuthToken(ensured);
      }
    } catch (_) {}

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
}
