import 'dart:io' show Platform;
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

class SecureTokenStore {
  SecureTokenStore._();

  static const _storage = FlutterSecureStorage();
  static const String _authTokenKey = 'auth_token';
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Detecta primera ejecución post-instalación para limpiar Keychain iOS que persiste entre reinstalaciones][obj: SecureTokenStore._firstRunKey]
  static const String _firstRunKey = 'secure_store_initialized';

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Limpia el Keychain en primera ejecución post-instalación. En iOS el Keychain sobrevive reinstalaciones pero SharedPreferences no — usamos esa diferencia como señal][obj: SecureTokenStore.clearOnFirstRun]
  static Future<void> clearOnFirstRun() async {
    if (!Platform.isIOS) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final initialized = prefs.getBool(_firstRunKey) ?? false;
      if (!initialized) {
        logInfo(
          'SecureTokenStore: primera ejecución detectada, limpiando Keychain',
        );
        await _storage.deleteAll();
        await _syncToNative(null);
        await prefs.setBool(_firstRunKey, true);
      }
    } catch (e) {
      logWarn('SecureTokenStore: clearOnFirstRun falló', details: e.toString());
    }
  }

  static const MethodChannel _channel = MethodChannel(
    'pe.gob.onp.thaqhiri/secure_store',
  );

  static String? normalizeAuthToken(String? token) {
    if (token == null) return null;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('{') && trimmed.contains('"token"')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final nested = decoded['token'];
          if (nested is String && nested.trim().isNotEmpty) {
            return nested.trim();
          }
        }
      } catch (_) {}
    }

    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }

    return trimmed;
  }

  static Future<void> writeAuthToken(String? token) async {
    token = normalizeAuthToken(token);
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _authTokenKey);
      await _syncToNative(null);
      return;
    }
    await _storage.write(key: _authTokenKey, value: token);
    await _syncToNative(token);
  }

  static Future<String?> readAuthToken() async {
    final token = normalizeAuthToken(await _storage.read(key: _authTokenKey));
    if (token == null || token.isEmpty) return null;
    return token;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Sincroniza auth_token también con iOS para que el flush nativo background tenga acceso explícito al token][obj: SecureTokenStore._syncToNative ios]
  static Future<void> _syncToNative(String? token) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final action = (token == null || token.isEmpty) ? 'clearToken' : 'setToken';
    try {
      if (token == null || token.isEmpty) {
        await _channel.invokeMethod('clearToken');
      } else {
        await _channel.invokeMethod('setToken', {'token': token});
      }
      logInfo('SecureTokenStore: sync nativo OK', details: action);
    } catch (e) {
      logWarn('SecureTokenStore: sync nativo FALLÓ', details: '$action | $e');
    }
  }
}
