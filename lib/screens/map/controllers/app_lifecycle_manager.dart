import 'package:get_it/get_it.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/telemetry_log_service.dart';
import '../../../services/background_schedule_manager.dart';
import 'map_screen_controller.dart';
import 'tracking_controller.dart';
import '../../../utils/logger.dart';

class AppLifecycleManager extends WidgetsBindingObserver {
  final TrackingController trackingController;
  final MapScreenController stateController;
  final ApiService apiService;
  
  // Callbacks a MapScreen
  final VoidCallback onStartBackgroundFlushTimer;
  final VoidCallback onStopBackgroundFlushTimer;
  final VoidCallback onStartTokenRefreshTimer;
  final Future<void> Function() onHydrateRouteFromBackground;
  final Future<void> Function() onRefreshPendingRouteFromLocal;
  final Function(String) onNotifyTrackingModeSwitch;
  final Function(String) onError;
  final VoidCallback onOutsideSchedule;
  final bool Function() getEnforceEndHour;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Callback para chequeo inmediato de llegada al volver al foreground, sin esperar primer GPS update][obj: AppLifecycleManager.onCheckArrivalOnResume]
  final Future<void> Function()? onCheckArrivalOnResume;

  AppLifecycleManager({
    required this.trackingController,
    required this.stateController,
    required this.apiService,
    required this.onStartBackgroundFlushTimer,
    required this.onStopBackgroundFlushTimer,
    required this.onStartTokenRefreshTimer,
    required this.onHydrateRouteFromBackground,
    required this.onRefreshPendingRouteFromLocal,
    required this.onNotifyTrackingModeSwitch,
    required this.onError,
    required this.onOutsideSchedule,
    required this.getEnforceEndHour,
    this.onCheckArrivalOnResume,
  });

  bool _shouldResumeTracking = false;
  bool _isInForeground = true;

  bool get isInForeground => _isInForeground;

  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onNotifyTrackingModeSwitch('app en primer plano');
      unawaited(
        GetIt.I<TelemetryLogService>().log('App en primer plano (lifecycle: resumed)'),
      );
      _isInForeground = true;
      // ignore: discarded_futures
      _handleAppResumed();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      onNotifyTrackingModeSwitch('app en segundo plano');
      unawaited(
        GetIt.I<TelemetryLogService>().log('App en segundo plano (lifecycle: ${state.name})'),
      );
      _isInForeground = false;
      // ignore: discarded_futures
      _handleAppBackgrounded();
    }
  }

  Future<void> _handleAppBackgrounded() async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: iOS no tiene servicio nativo equivalente a Android; LocationTracker.swift requiere permiso Always que puede no estar otorgado. Se mantiene el geolocator activo en background (allowBackgroundLocationUpdates=true + UIBackgroundModes:location). Solo Android delega a servicio nativo.][obj: AppLifecycleManager._handleAppBackgrounded ios keep geolocator]
    final shouldDelegateToNative = defaultTargetPlatform == TargetPlatform.android;

    if (!shouldDelegateToNative) {
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          'Tracking Flutter: background iOS (geolocator activo, nativo_continuo=${trackingController.nativeAlwaysOn})',
        ),
      );
      onStartBackgroundFlushTimer();
      return;
    }

    if (trackingController.isTracking) {
      _shouldResumeTracking = true;
      try {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 19:05 UTC-5 (Lima)][desc: En Android inicia nativo explícitamente antes de apagar Flutter para no depender solo de enforceNow][obj: AppLifecycleManager._handleAppBackgrounded robust native handoff]
        if (defaultTargetPlatform == TargetPlatform.android) {
          await BackgroundScheduleManager.setForegroundTrackingActive(false);
          final nativeError = await BackgroundScheduleManager.startNativeTracking();
          unawaited(
            GetIt.I<TelemetryLogService>().log(
              nativeError == null
                  ? (trackingController.nativeAlwaysOn
                      ? 'Tracking nativo: inicio OK (siempre_activo=ON, fg_active=false)'
                      : 'Tracking nativo: inicio OK (app en segundo plano, fg_active=false)')
                  : 'Tracking nativo: ERROR al iniciar en background (error=$nativeError)',
            ),
          );
        }
        await trackingController.stopTracking(
          stopNativeTracking: false,
          markForegroundTrackingInactive: defaultTargetPlatform != TargetPlatform.android,
        );
        stateController.setTrackingState(
          isTracking: trackingController.isTracking,
          waitingInitialFix: trackingController.waitingInitialFix,
        );
      } catch (e) {
        logWarn(
          'No se pudo detener tracking foreground al background',
          details: e.toString(),
        );
      }
    } else {
      _shouldResumeTracking = true;
    }
    
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:35 UTC-5 (Lima)][desc: En background, fuerza flush de pendientes cada 2 min]
    onStartBackgroundFlushTimer();
    
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:41 UTC-5 (Lima)][desc: Programa flush nativo (AlarmManager) en background con log local]
    logDebug('Programando flush nativo en background');
    await BackgroundScheduleManager.schedulePendingFlush();
    try {
      await BackgroundScheduleManager.setForegroundTrackingActive(false);
      await BackgroundScheduleManager.enforceNow();
    } catch (e) {
      logWarn(
        'No se pudo forzar tracking nativo al background',
        details: e.toString(),
      );
    }
  }

  Future<void> _handleAppResumed() async {
    try {
      await GetIt.I<AuthService>().restoreSession();
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 10:18 UTC-5 (Lima)][desc: Renueva token solo si está por expirar según claim exp]
      final token = await GetIt.I<AuthService>().ensureValidToken();
      await apiService.updateAuthToken(token);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:22 UTC-5 (Lima)][desc: Al volver al foreground, completa ruta con puntos capturados en background]
      await onHydrateRouteFromBackground();
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:30 UTC-5 (Lima)][desc: Actualiza ruta pendiente desde DB local para pintar en color alterno]
      await onRefreshPendingRouteFromLocal();
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Loguea resultado del último flush nativo y horario guardado para diagnosticar captura en background][obj: AppLifecycleManager._handleAppResumed bg flush diagnostics]
      try {
        final prefs = await SharedPreferences.getInstance();
        final flushAt = prefs.getString('bg_flush_last_at') ?? 'nunca';
        final flushStatus = prefs.getString('bg_flush_last_status') ?? 'sin_estado';
        final horaInicio = prefs.getInt('bg_hora_inicio');
        final horaFin = prefs.getInt('bg_hora_fin');
        unawaited(
          GetIt.I<TelemetryLogService>().log(
            'Diagnóstico background: flush_at=$flushAt flush_status=$flushStatus horario=${horaInicio ?? "?"}h-${horaFin ?? "?"}h',
          ),
        );
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Loguea último punto capturado por el servicio nativo y conteo de pendientes en SQLite nativo][obj: AppLifecycleManager._handleAppResumed native sqlite telemetry]
        final nativeSqliteCount = prefs.getInt('native_sqlite_count') ?? -1;
        if (nativeSqliteCount >= 0) {
          final nativeLatBits = prefs.getInt('native_last_lat');
          final nativeLngBits = prefs.getInt('native_last_lng');
          final nativeLat = _longBitsToDouble(nativeLatBits);
          final nativeLng = _longBitsToDouble(nativeLngBits);
          final coordStr = (nativeLat != null && nativeLng != null)
              ? 'lat=${nativeLat.toStringAsFixed(6)} lng=${nativeLng.toStringAsFixed(6)}'
              : 'coords=sin_dato';
          unawaited(
            GetIt.I<TelemetryLogService>().log(
              'SQLite nativo: pendientes=$nativeSqliteCount último_punto=$coordStr',
            ),
          );
        }
      } catch (_) {}
    } catch (e) {
      logWarn(
        'No se pudo restaurar sesión/token al volver al foreground',
        details: e.toString(),
      );
    }

    if (_shouldResumeTracking) {
      _shouldResumeTracking = false;
      final ok = await trackingController.startTracking(
        onError: onError,
        onOutsideSchedule: onOutsideSchedule,
        enforceEndHour: getEnforceEndHour(),
      );
      stateController.setTrackingState(
        isTracking: trackingController.isTracking,
        waitingInitialFix: trackingController.waitingInitialFix,
      );
      if (!ok) {
        logWarn('No se pudo reactivar tracking al volver al foreground');
      }
    }

    onStartTokenRefreshTimer();
    
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:35 UTC-5 (Lima)][desc: Detiene flush periódico al volver a foreground]
    onStopBackgroundFlushTimer();
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:41 UTC-5 (Lima)][desc: Cancela flush nativo al volver a foreground con log local]
    logDebug('Cancelando flush nativo al foreground');
    await BackgroundScheduleManager.cancelPendingFlush();

    try {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Modo nativo exclusivo en Android: no marcar fg_tracking_active=true para no cancelar el flush de pendientes del nativo][obj: AppLifecycleManager._handleAppResumed native_exclusive]
      final fgActive = trackingController.isTracking &&
          !(trackingController.nativeAlwaysOn &&
              defaultTargetPlatform == TargetPlatform.android);
      await BackgroundScheduleManager.setForegroundTrackingActive(fgActive);
      await BackgroundScheduleManager.enforceNow();
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          trackingController.nativeAlwaysOn
              ? 'Tracking Flutter: foreground (nativo_continuo=ON, fg_active=$fgActive)'
              : 'Tracking Flutter: foreground (nativo_continuo=OFF, fg_active=$fgActive)',
        ),
      );
    } catch (e) {
      logWarn(
        'No se pudo sincronizar estado de tracking al volver al foreground',
        details: e.toString(),
      );
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Chequeo inmediato de llegada al volver al foreground usando última posición conocida, sin esperar el primer GPS update][obj: AppLifecycleManager._handleAppResumed checkArrival]
    final checkArrival = onCheckArrivalOnResume;
    if (checkArrival != null) unawaited(checkArrival());
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Convierte bits raw (int de SharedPreferences) a double, igual que Java Double.longBitsToDouble][obj: AppLifecycleManager._longBitsToDouble]
  double? _longBitsToDouble(int? bits) {
    if (bits == null) return null;
    final bd = ByteData(8);
    bd.setInt64(0, bits);
    return bd.getFloat64(0);
  }
}
