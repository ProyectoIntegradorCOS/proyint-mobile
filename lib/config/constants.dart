import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

class Constants {
  Constants._();

  static String _dotenvValue(String key) => dotenv.env[key]?.trim() ?? '';

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Permite sobreescribir la URL del backend en tiempo de compilación
  /// usando `--dart-define=API_BASE_URL=...`.
  static const String _definedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );
  static String get _envApiBaseUrl => _dotenvValue('URL_BACKEND');

  /// Base URL del backend, ajustada según la plataforma y/o `--dart-define`.
  static String get apiBaseUrl {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 17:26 UTC-5 (Lima)][desc: Hace explícita la prioridad de configuración: primero --dart-define, luego .env y al final fallback por plataforma][obj: Constants.apiBaseUrl priority]
    // Prioridad 1: valor provisto por --dart-define
    if (_definedApiBaseUrl.isNotEmpty) {
      return _definedApiBaseUrl;
    }

    // Prioridad 2: valor provisto por .env (URL_BACKEND)
    if (_envApiBaseUrl.isNotEmpty) {
      return _envApiBaseUrl;
    }

    // Prioridad 3: valores por defecto según plataforma/entorno
    if (kIsWeb) {
      return 'http://localhost:5511/api';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:5511/api';
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 17:33 UTC-5 (Lima)][desc: Evita fallback engañoso a localhost en iOS/desktop cuando no hay configuración explícita del backend][obj: Constants.apiBaseUrl non-android fallback]
    return '';
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 17:26 UTC-5 (Lima)][desc: Log centralizado de configuración efectiva para backend y SAA; ayuda a confirmar qué fuente de datos terminó ganando][obj: Constants.logResolvedConfig]
  static void logResolvedConfig() {
    logDebug(
      'Config efectiva',
      details: 'apiBaseUrl=$apiBaseUrl',
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 17:26 UTC-5 (Lima)][desc: Validación central de configuración obligatoria; devuelve mensajes concretos para diagnóstico temprano][obj: Constants.validateRequiredConfig]
  static List<String> validateRequiredConfig() {
    final issues = <String>[];
    if (apiBaseUrl.isEmpty) {
      issues.add('API_BASE_URL/URL_BACKEND no configurado');
    }
    return issues;
  }

  /// Mostrar un preview del token SAA en UI para pruebas.
  /// Puede activarse/desactivarse en runtime si se recompila, o cambiarlo aquí.
  static const bool showAuthTokenPreview = false; // poner en true para ver el token en UI
}
