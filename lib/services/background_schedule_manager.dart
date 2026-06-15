// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Manager para persistir horario y programar alarmas exactas (AlarmManager/BGTaskScheduler) vía MethodChannel][obj: BackgroundScheduleManager]
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:30 UTC-5 (Lima)][desc: Neutraliza referencias "Android" en logs; canal ahora también activo en iOS][obj: BackgroundScheduleManager logs]
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../utils/logger.dart';

class BackgroundScheduleManager {
  BackgroundScheduleManager._();

  static const MethodChannel _channel = MethodChannel(
    'pe.gob.onp.thaqhiri/background_schedule',
  );

  /// Persiste el horario y programa alarmas exactas en Android.
  ///
  /// Requisitos:
  /// - `auth_token` y `auth_uid` deben existir en SharedPreferences.
  /// - `API_BASE_URL` debe ser alcanzable desde el dispositivo.
  static Future<void> upsertScheduleAndProgramAlarms({
    required int horarioId,
    required int horaInicio,
    required int horaFin,
    String? horarioNombre,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_base_url', Constants.apiBaseUrl);
      await prefs.setInt('bg_horario_id', horarioId);
      await prefs.setInt('bg_hora_inicio', horaInicio);
      await prefs.setInt('bg_hora_fin', horaFin);
      if (horarioNombre != null) {
        await prefs.setString('bg_horario_nombre', horarioNombre);
      }
      await prefs.setString(
        'bg_horario_updated_at',
        DateTime.now().toIso8601String(),
      );

      await _channel.invokeMethod('scheduleAlarms');
      logDebug(
        'Alarmas programadas',
        details: 'horarioId=$horarioId $horaInicio-$horaFin',
      );
    } catch (e, st) {
      logError(
        'No se pudo programar alarmas',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Future<void> cancelAlarms() async {
    try {
      await _channel.invokeMethod('cancelAlarms');
    } catch (e, st) {
      logError('No se pudo cancelar alarmas', error: e, stackTrace: st);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Fuerza enforce del window de tracking inmediatamente (para continuar tracking tras logout dentro de horario)][obj: BackgroundScheduleManager.enforceNow]
  static Future<void> enforceNow() async {
    try {
      await _channel.invokeMethod('enforceNow');
      logDebug('enforceNow ejecutado');
    } catch (e, st) {
      logError('No se pudo ejecutar enforceNow', error: e, stackTrace: st);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Informa al tracker nativo si el tracking foreground (Flutter) está activo para evitar doble tracking nativo+flutter][obj: BackgroundScheduleManager.setForegroundTrackingActive]
  static Future<void> setForegroundTrackingActive(bool active) async {
    try {
      await _channel.invokeMethod(
        'setForegroundTrackingActive',
        {'active': active},
      );
      logDebug(
        'setForegroundTrackingActive',
        details: 'active=$active',
      );
    } catch (e, st) {
      logError(
        'No se pudo setForegroundTrackingActive',
        error: e,
        stackTrace: st,
      );
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:45 UTC-5 (Lima)][desc: Programa/cancela flush nativo de pendientes en background (AlarmManager/BGTaskScheduler)][obj: BackgroundScheduleManager pending flush]
  static Future<void> schedulePendingFlush() async {
    try {
      await _channel.invokeMethod('schedulePendingFlush');
      logDebug('schedulePendingFlush ejecutado');
    } catch (e, st) {
      logError('No se pudo programar schedulePendingFlush', error: e, stackTrace: st);
    }
  }

  static Future<void> cancelPendingFlush() async {
    try {
      await _channel.invokeMethod('cancelPendingFlush');
      logDebug('cancelPendingFlush ejecutado');
    } catch (e, st) {
      logError('No se pudo cancelar cancelPendingFlush', error: e, stackTrace: st);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 UTC-5 (Lima)][desc: Controla tracking nativo continuo (ForegroundService/CLLocationManager)][obj: BackgroundScheduleManager.native_tracking]
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Retorna mensaje de error para que el caller pueda loguear en telemetría][obj: BackgroundScheduleManager.startNativeTracking error propagation]
  static Future<String?> startNativeTracking() async {
    try {
      await _channel.invokeMethod('startNativeTracking');
      logDebug('startNativeTracking ejecutado');
      return null;
    } on PlatformException catch (e, st) {
      logError('No se pudo ejecutar startNativeTracking', error: e, stackTrace: st);
      return '${e.code}: ${e.message}';
    } catch (e, st) {
      logError('No se pudo ejecutar startNativeTracking', error: e, stackTrace: st);
      return e.toString();
    }
  }

  static Future<void> stopNativeTracking() async {
    try {
      await _channel.invokeMethod('stopNativeTracking');
      logDebug('stopNativeTracking ejecutado');
    } catch (e, st) {
      logError('No se pudo ejecutar stopNativeTracking', error: e, stackTrace: st);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Flush inmediato del SQLite nativo al backend (para llamar al abrir la app o hacer login)][obj: BackgroundScheduleManager.flushNativePendingNow]
  static Future<String> flushNativePendingNow() async {
    try {
      final result = await _channel.invokeMethod<String>('flushNativePendingNow');
      return result ?? 'ok';
    } catch (e, st) {
      logError('No se pudo ejecutar flushNativePendingNow', error: e, stackTrace: st);
      return 'error: $e';
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Obtiene conteo de puntos pendientes en SQLite nativo para diagnóstico][obj: BackgroundScheduleManager.getNativeSqliteCount]
  static Future<int> getNativeSqliteCount() async {
    try {
      final count = await _channel.invokeMethod<int>('getNativeSqliteCount');
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
