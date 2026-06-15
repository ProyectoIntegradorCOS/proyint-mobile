import 'dart:async';
import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/background_schedule_manager.dart';
import '../../../services/identity_service.dart';
import '../../../services/location_service.dart';
import '../../../services/logout_flush_service.dart';
import '../../../utils/logger.dart';
import '../../visits/visit_plan_screen.dart';
import '../../../models/visit_plan.dart';
import 'map_screen_controller.dart';
import 'tracking_controller.dart';

class AuthFlowController {
  final AuthService authService;
  final IdentityService identityService;
  final LocationService locationService;
  final ApiService apiService;
  final MapScreenController stateController;
  final TrackingController trackingController;
  // We need to know if a visit is in progress. VisitController doesn't track "active plan visit" state directly
  // in the same way MapScreen did with _activePlanVisit.
  // However, MapScreen had _activePlanVisit. We might need to pass this info or refactor VisitController to track it.
  // For now, let's assume we can check VisitController or we pass the check logic.
  // Actually, MapScreen logic for _ensureVisitFinishedBeforeLogout used _activePlanVisit.
  // We should probably move _activePlanVisit to VisitController or keep it here if it's flow specific.
  // But VisitController seems like the right place.
  // Let's assume for this refactor we might need to ask MapScreen or VisitController.
  // To keep it clean, let's pass a callback or check VisitController if it has that state.
  // Looking at MapScreen, _activePlanVisit is set in _startVisitReminder.
  // _visitController has startVisitReminder but doesn't seem to expose the active visit item directly as a property?
  // Let's check VisitController.

  final Function() onLogoutSuccess;

  AuthFlowController({
    required this.authService,
    required this.identityService,
    required this.locationService,
    required this.apiService,
    required this.stateController,
    required this.trackingController,
    required this.onLogoutSuccess,
  });

  Future<void> attemptLogout(
    BuildContext context, {
    required bool hasVisitInProgress,
  }) async {
    final canLogout = await _ensureVisitFinishedBeforeLogout(
      context,
      hasVisitInProgress,
    );
    if (!canLogout) return;

    if (trackingController.isTracking) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Detiene tracking foreground vía TrackingController para desmarcar fg_tracking_active (evita bloquear tracking nativo tras logout)][obj: AuthFlowController.attemptLogout stopTracking]
      await trackingController.stopTracking();
      // Update state via controller
      stateController.setTrackingState(
        isTracking: false,
        waitingInitialFix: false,
      );
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Envía ubicaciones pendientes antes de cerrar sesión (sin esperar batchSize)][obj: AuthFlowController.attemptLogout]
    final token = authService.currentSession?.token;
    final uid = authService.currentSession?.uid;
    if (token != null && token.isNotEmpty) {
      if (uid != null && uid.isNotEmpty) {
        await LogoutFlushService.flushPendingBeforeLogout(uid: uid, token: token);
      }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Evicta el token del cache Caffeine del backend antes de limpiar localmente, garantizando que el token no sea aceptado durante el TTL residual][obj: AuthFlowController.attemptLogout evictToken]
    if (token != null && token.isNotEmpty) {
      await apiService.evictToken(token);
    }
    logInfo('attemptLogout: token eliminado del APP (updateAuthToken null)');
    await apiService.updateAuthToken(null);
    LogoutResult res;
    try {
      res = await authService.signOutSaa();
    } catch (e, st) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Si falla logout remoto, asegura logout local y continúa enforceNow para tracking por horario][obj: AuthFlowController.attemptLogout signOutSaa catch]
      logError('signOutSaa falló (attemptLogout)', error: e, stackTrace: st);
      await authService.signOut();
      res = LogoutResult(
        resultado: '4',
        mensaje: 'ERROR al cerrar sesión',
        success: false,
      );
    } finally {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Asegura fg_tracking_active=false antes de enforceNow para permitir tracking nativo sin sesión dentro del horario][obj: AuthFlowController.attemptLogout fg_tracking_active]
      await BackgroundScheduleManager.setForegroundTrackingActive(false);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Tras logout real (ok o fallo), fuerza enforceNow para aplicar tracking por horario][obj: AuthFlowController.attemptLogout enforceNow finally]
      await BackgroundScheduleManager.enforceNow();
    }

    if (context.mounted) {
      Color bg;
      String text;
      switch (res.resultado) {
        case '1':
          bg = Colors.red; // Sesión Cerrada (mostrar en rojo)
          text = res.mensaje.isNotEmpty ? res.mensaje : 'Sesión Cerrada';
          break;
        case '2':
          bg = Colors.red; // Sesión no Cerrada
          text = res.mensaje.isNotEmpty ? res.mensaje : 'Sesión no Cerrada';
          break;
        case '3':
          bg = Colors.amber; // Token vacío
          text = res.mensaje.isNotEmpty
              ? res.mensaje
              : 'El token debe ser distinto de vacío';
          break;
        case '5':
          bg = Colors.deepOrange; // Token inválido
          text = res.mensaje.isNotEmpty ? res.mensaje : 'Token inválido';
          break;
        case '6':
          bg = Colors.deepOrange; // Token expirado
          text = res.mensaje.isNotEmpty ? res.mensaje : 'Token expirado';
          break;
        case '4':
        default:
          bg = Colors.red; // ERROR u otro
          text = res.mensaje.isNotEmpty
              ? res.mensaje
              : 'ERROR al cerrar sesión';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('[${res.resultado}] $text'),
          backgroundColor: bg,
          duration: const Duration(seconds: 3),
        ),
      );

      onLogoutSuccess();
    }
  }

  Future<void> forceLogout() async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Flush best-effort antes de logout forzado][obj: AuthFlowController.forceLogout]
    final token = authService.currentSession?.token;
    final uid = authService.currentSession?.uid;
    if (token != null && token.isNotEmpty) {
      if (uid != null && uid.isNotEmpty) {
        await LogoutFlushService.flushPendingBeforeLogout(uid: uid, token: token);
      }
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Asegura fg_tracking_active=false en logout forzado para permitir tracking nativo por horario][obj: AuthFlowController.forceLogout fg_tracking_active]
    await BackgroundScheduleManager.setForegroundTrackingActive(false);
    try {
      await authService.signOutSaa();
    } catch (_) {
      await authService.signOut();
    } finally {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Tras logout forzado, fuerza enforceNow para que el servicio nativo aplique ventana horaria][obj: AuthFlowController.forceLogout enforceNow]
      await BackgroundScheduleManager.enforceNow();
    }
    await identityService.clearHorario();
  }

  Future<bool> _ensureVisitFinishedBeforeLogout(
    BuildContext context,
    bool hasVisitInProgress,
  ) async {
    if (!hasVisitInProgress) return true;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Visita en curso'),
        content: const Text(
          'Tienes una visita en curso. Debes finalizarla antes de cerrar sesión. ¿Deseas completarla ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Seguir en la app'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('complete'),
            child: const Text('Completar visita'),
          ),
        ],
      ),
    );

    if (action != 'complete') return false;

    if (!context.mounted) return false;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisitPlanScreen(apiService: apiService),
      ),
    );

    if (result is VisitItem && result.state == VisitItemState.done) {
      // We need to stop the reminder.
      // This logic was in MapScreen: _stopVisitReminder().
      // We should probably return true here and let MapScreen handle the stop,
      // or pass a callback to stop it.
      // Since we are moving logic, let's assume the caller handles the UI update or we pass a callback.
      return true;
    }
    return false;
  }
}
