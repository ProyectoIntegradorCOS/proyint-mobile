import 'package:get_it/get_it.dart';
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:55 UTC-5 (Lima)][desc: Agrega import de LatLng faltante][obj: MapInitializationService imports]
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/constants.dart';
import '../../../services/api_service.dart';
import '../../../services/identity_service.dart';
import '../../../services/location_service.dart';
import '../../../services/location_sync_manager.dart';
import '../../../services/background_schedule_manager.dart';
import '../../../utils/logger.dart';
import 'map_screen_controller.dart';
import 'tracking_controller.dart';
import 'visit_controller.dart';
import 'route_controller.dart';

class MapInitializationService {
  final MapScreenController stateController;
  final TrackingController trackingController;
  final VisitController visitController;
  final RouteController routeController;
  final ApiService apiService;
  final LocationService locationService;
  final LocationSyncManager syncManager;

  MapInitializationService({
    required this.stateController,
    required this.trackingController,
    required this.visitController,
    required this.routeController,
    required this.apiService,
    required this.locationService,
    required this.syncManager,
  });

  Future<void> bootstrap({
    required BuildContext context,
    required Function(String?) onConnectionMessage,
    required Function(String?) onShutdownMessage,
    required Function(String) onError,
    required Function(LatLng) onMoveCamera,
    required Function() onOutsideSchedule,
    required bool enforceEndHour,
    required bool showSchedulePrompt,
    required Function() onShowSchedulePrompt,
  }) async {
    logDebug('MapScreen bootstrap iniciado (Service)');
    try {
      onShutdownMessage(null);
      onConnectionMessage(null);

      stateController.clearMessages();
      stateController.resetVisits();
      trackingController.resetScheduleHandled();
      
      final identity = GetIt.I<IdentityService>();
      await identity.ensureHorarioLoaded();
      
      final uid = identity.uid;
      final email = identity.email;
      if (!context.mounted) return;
      final startHour = identity.horarioInicio;
      final endHour = identity.horarioFin;
      
      if (startHour != null && endHour != null) {
        trackingController.updateSchedule(
          startHour: startHour,
          endHour: endHour,
        );
      }
      
      if (uid == null || email == null) {
        onError('Sesión no válida. Inicia sesión nuevamente.');
        return;
      }
      logDebug('Identidad cargada', details: 'uid=$uid permisos=${identity.permisos.join(', ')}');
      
      final token = await identity.getIdToken();
      if (token == null) {
        logDebug('No se pudo obtener ID token de Firebase');
      }
      await apiService.updateAuthToken(token);
      if (!context.mounted) return;
      
      if (context.mounted &&
          token != null &&
          token.isNotEmpty &&
          Constants.showAuthTokenPreview) {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Evita mostrar token SAA en UI (solo longitud) para reducir riesgo de fuga][obj: MapInitializationService token preview]
        final preview = 'len=${token.length}';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Token SAA: $preview'),
              duration: const Duration(seconds: 6),
            ),
          );
        });
      }
      
      await _syncScheduleFromServer(uid);
      if (!context.mounted) return;
      logDebug('Horario sincronizado, backend ready');
      
      final ready = await _ensureBackendReady(onError);
      if (!ready) {
        onConnectionMessage(
          'No se pudo conectar con el servidor. Reintenta en unos segundos.',
        );
        return;
      }

      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Carga plan de visitas real al iniciar mapa][obj: MapInitializationService.bootstrap]
      try {
        await visitController.loadVisits();
        if (!context.mounted) return;
        logDebug(
          'Visitas cargadas',
          details: 'total=${visitController.todayVisits.length}',
        );
        stateController.setVisits(
          visitController.todayVisits,
          currentIndex: visitController.currentVisitIndex,
        );
        for (final id in visitController.completedVisitIds) {
          stateController.markVisitCompletedById(id);
        }
      } catch (e) {
        logError('No se pudieron cargar las visitas', error: e);
      }
      
      if (!_isWithinTrackingWindow(DateTime.now())) {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 16:09 UTC-5 (Lima)][desc: Fuera de horario solo detiene tracking; no bloquea el uso del app][obj: MapInitializationService.bootstrap]
        onOutsideSchedule();
      }
      
      await _loadPreferences();
      if (!context.mounted) return;
      
      final p = await locationService.getCurrentOnce();
      if (!context.mounted) return;
      if (p != null) {
        onMoveCamera(LatLng(p.latitude, p.longitude));
      }
      
      stateController.setShowingHistory(false);
      if (!context.mounted) return;
      
      await startTracking(
        ensureBackend: false,
        onError: onError,
        onOutsideSchedule: onOutsideSchedule,
        enforceEndHour: enforceEndHour,
        context: context,
      );
      
      if (showSchedulePrompt) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            onShowSchedulePrompt();
          }
        });
      }
      
    } catch (e) {
      logError('Error inicializando', error: e);
      onError('Error inicializando: $e');
    } finally {
      if (context.mounted) {
        stateController.setIsLoading(false);
      }
      logDebug('Bootstrap completado (Service)');
    }
  }

  Future<void> _syncScheduleFromServer(String uid) async {
    try {
      final idSvc = GetIt.I<IdentityService>();
      logDebug("uid :"+uid);
      final profile = await apiService.fetchUserProfile(uid);
      if (profile != null && profile.horarioId != null) {
        final horario = await apiService.fetchHorarioById(profile.horarioId!);
        await GetIt.I<IdentityService>().setHorario(
          inicio: horario.horaInicio,
          fin: horario.horaFin,
        );
        trackingController.updateSchedule(
          startHour: horario.horaInicio,
          endHour: horario.horaFin,
        );
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 16:50 UTC-5 (Lima)][desc: Sincroniza horario con el scheduler nativo de Android al descargar del servidor][obj: MapInitializationService._syncScheduleFromServer native sync]
        await BackgroundScheduleManager.upsertScheduleAndProgramAlarms(
          horarioId: horario.id,
          horaInicio: horario.horaInicio,
          horaFin: horario.horaFin,
          horarioNombre: horario.nombre,
        );
      }
    } catch (e, st) {
      logError('No se pudo sincronizar horario', error: e, stackTrace: st);
    }
  }

  Future<bool> _ensureBackendReady(Function(String) onError) async {
    if (stateController.backendReady) return true;
    final uid = GetIt.I<IdentityService>().uid;
    if (uid == null) {
      onError('No hay identidad para continuar');
      return false;
    }
    try {
      final token = await GetIt.I<IdentityService>().getIdToken();
      await apiService.updateAuthToken(token);
      stateController.setBackendReady(true);
      logDebug('Backend listo para envío de datos');
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Mantiene flush de pendientes por usuario al marcar backend listo (cola por uid)][obj: MapInitializationService._ensureBackendReady]
      await _tryFlushPending(onError);
      return true;
    } catch (e) {
      onError('No se pudo registrar el usuario: $e');
      logError('Fallo de backend al registrar usuario', error: e);
      return false;
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Resuelve uid dentro del método para evitar mezclar colas entre sesiones][obj: MapInitializationService._tryFlushPending resolve uid]
  Future<void> _tryFlushPending(Function(String) onError) async {
    try {
      final uid = GetIt.I<IdentityService>().uid;
      if (uid == null || uid.isEmpty) return;
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Flush por usuario para evitar mezclar colas entre sesiones][obj: MapInitializationService._tryFlushPending]
      await syncManager.flushPending(firebaseUid: uid);
      logDebug('Flush de ubicaciones pendientes finalizado');
    } catch (e) {
      onError('Quedan ubicaciones pendientes: $e');
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = prefs.getDouble('arrival_radius_m');
      final m = prefs.getInt('dwell_minutes');
      // final bl = prefs.getString('base_layer'); // Base layer handled in UI or separate controller
      // final reminder = prefs.getInt('visit_reminder_minutes'); // Handled in UI/VisitController
      
      if (r != null) {
        visitController.configureArrivalDetection(radiusMeters: r);
      } else {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-20 00:00 UTC-5 (Lima)][desc: Persiste radio de llegada por defecto][obj: MapInitializationService._loadPreferences arrival default]
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Aplica el radio por defecto también al controlador para que el modal use 100m y no el hardcoded 50m][obj: MapInitializationService._loadPreferences arrival default apply]
        visitController.configureArrivalDetection(radiusMeters: 100.0);
        await prefs.setDouble('arrival_radius_m', 100.0);
      }
      if (m != null) {
        visitController.configureArrivalDetection(
          dwellDuration: Duration(minutes: m),
        );
      }
    } catch (_) {}
  }

  bool _isWithinTrackingWindow(DateTime timestamp) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 18:36 UTC-5 (Lima)][desc: Restringe tracking a días hábiles (L-V)][obj: MapInitializationService._isWithinTrackingWindow weekday guard]
    if (timestamp.weekday == DateTime.saturday ||
        timestamp.weekday == DateTime.sunday) {
      return false;
    }
    final start = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
      trackingController.trackingStartHour,
    );
    final end = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
      trackingController.trackingEndHour,
    );
    return !timestamp.isBefore(start) && !timestamp.isAfter(end);
  }

  Future<void> startTracking({
    required bool ensureBackend,
    required Function(String) onError,
    required Function() onOutsideSchedule,
    required bool enforceEndHour,
    required BuildContext context,
  }) async {
    if (trackingController.isTracking) return;

    try {
      if (ensureBackend) {
        final ready = await _ensureBackendReady(onError);
        if (!ready) return;
      }

      logDebug('Tracking iniciado (Service)');

      final success = await trackingController.startTracking(
        onError: onError,
        onOutsideSchedule: onOutsideSchedule,
      );

      if (!success) return;

      stateController.setTrackingState(
        isTracking: true,
        waitingInitialFix: true,
      );
      
      if (enforceEndHour) {
         await trackingController.startTracking(
            onError: onError,
            onOutsideSchedule: onOutsideSchedule,
            enforceEndHour: true,
          );
      }
      
      if (!routeController.startNotified && context.mounted) {
        routeController.markRouteStarted();
      }
    } catch (e) {
      onError('Error iniciando tracking: $e');
      stateController.setShowingHistory(false);
      stateController.setTrackingState(
        isTracking: false,
        waitingInitialFix: false,
      );
    }
  }
}
