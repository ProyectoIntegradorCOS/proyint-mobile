import 'package:get_it/get_it.dart';
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:15 UTC-5 (Lima)][desc: Corrige imports de servicios y modelos][obj: TrackingController imports]
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/location_service.dart';
import '../../../services/location_sync_manager.dart';
import '../../../services/background_schedule_manager.dart';
import '../../../services/identity_service.dart';
import '../../../services/telemetry_log_service.dart';
import '../../../models/location_point.dart';
import '../../../utils/logger.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:45 UTC-5 (Lima)][desc: Crea controlador especializado para lógica de tracking GPS][obj: TrackingController]
class TrackingController extends ChangeNotifier {
  final LocationService _locationService;
  final LocationSyncManager _syncManager;

  TrackingController({
    required LocationService locationService,
    required LocationSyncManager syncManager,
  })  : _locationService = locationService,
        _syncManager = syncManager {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 16:55 UTC-5 (Lima)][desc: Intenta cargar horario desde caché de identidad al instanciar][obj: TrackingController constructor init]
    _loadScheduleFromIdentity();
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-20 00:00 UTC-5 (Lima)][desc: Carga ajustes de filtros de tracking desde preferencias][obj: TrackingController constructor prefs]
    unawaited(_loadTrackingFilterPrefs());
  }

  void _loadScheduleFromIdentity() {
    final idSvc = GetIt.I<IdentityService>();
    if (idSvc.horarioInicio != null) _trackingStartHour = idSvc.horarioInicio!;
    if (idSvc.horarioFin != null) _trackingEndHour = idSvc.horarioFin!;
  }

  bool _isTracking = false;
  bool _waitingInitialFix = true;
  bool _outsideScheduleHandled = false;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 16:45 UTC-5 (Lima)][desc: Remueve valores en duro; se inicializan en null para forzar carga desde servicio/caché][obj: TrackingController schedule fields]
  int? _trackingStartHour;
  int? _trackingEndHour;
  Timer? _scheduleEnforcer;

  bool get isTracking => _isTracking;
  bool get waitingInitialFix => _waitingInitialFix;
  bool get outsideScheduleHandled => _outsideScheduleHandled;
  int get trackingStartHour => _trackingStartHour ?? 8; // Fallback de seguridad
  int get trackingEndHour => _trackingEndHour ?? 20; // Fallback de seguridad
  Timer? get scheduleEnforcer => _scheduleEnforcer;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:47 UTC-5 (Lima)][desc: Inicia tracking GPS con validación de horario][obj: TrackingController.startTracking]
  Future<bool> startTracking({
    required Function(String) onError,
    required Function() onOutsideSchedule,
    bool enforceEndHour = false,
  }) async {
    try {
      final now = DateTime.now();
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 18:38 UTC-5 (Lima)][desc: Muestra aviso específico si es fin de semana (no se permite tracking)][obj: TrackingController.startTracking weekend message]
      if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
        onError('El tracking está habilitado solo de lunes a viernes.');
        return false;
      }
      final hour = now.hour;

      // Validar horario
      if (hour < trackingStartHour || hour >= trackingEndHour) {
        if (!_outsideScheduleHandled) {
          onOutsideSchedule();
          _outsideScheduleHandled = true;
          notifyListeners();
        }
        return false;
      }

      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 16:35 UTC-5 (Lima)][desc: Solicita omitir optimización de batería para asegurar tracking continuo en Doze Mode][obj: TrackingController.startTracking battery optimization]
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:47 UTC-5 (Lima)][desc: Limita battery optimization a Android; no aplica en iOS][obj: TrackingController.startTracking battery optimization guard]
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }

      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Modo nativo exclusivo en Android: geolocator solo para display del mapa, nativo captura y envía puntos][obj: TrackingController.startTracking native_exclusive]
      if (_nativeAlwaysOn && defaultTargetPlatform == TargetPlatform.android) {
        await _locationService.start(settings: _criticalLocationSettings());
        _isTracking = true;
        _waitingInitialFix = true;
        final prefs = await SharedPreferences.getInstance();
        final trackingUid = prefs.getString('tracking_uid') ?? '(sin uid)';
        final nativeError = await BackgroundScheduleManager.startNativeTracking();
        unawaited(
          GetIt.I<TelemetryLogService>().log(
            nativeError == null
                ? 'Tracking nativo exclusivo: inicio (modo_real=Nativo, uid=$trackingUid)'
                : 'Tracking nativo exclusivo: ERROR al iniciar (uid=$trackingUid, error=$nativeError)',
          ),
        );
        if (enforceEndHour) _rescheduleScheduleEnforcer(onOutsideSchedule);
        notifyListeners();
        return true;
      }

      final useCritical = _alwaysCriticalTracking || _isWithinScheduleNow();
      await _locationService.start(
        settings: useCritical ? _criticalLocationSettings() : _captureSettings(),
      );
      _isTracking = true;
      _waitingInitialFix = true;
      unawaited(
        GetIt.I<TelemetryLogService>()
            .log('Tracking Flutter: inicio (modo_real=Flutter)'),
      );
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Marca tracking foreground activo para que Android detenga servicio nativo (evita doble encolado)][obj: TrackingController.startTracking fg_tracking_active]
      await BackgroundScheduleManager.setForegroundTrackingActive(true);
      if (enforceEndHour) _rescheduleScheduleEnforcer(onOutsideSchedule);
      notifyListeners();
      return true;
    } catch (e) {
      onError('Error al iniciar tracking: $e');
      return false;
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:48 UTC-5 (Lima)][desc: Detiene tracking GPS][obj: TrackingController.stopTracking]
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 19:05 UTC-5 (Lima)][desc: Permite detener solo el tracking Flutter sin apagar el nativo durante la transición a background][obj: TrackingController.stopTracking selective native stop]
  Future<void> stopTracking({
    bool stopNativeTracking = true,
    bool markForegroundTrackingInactive = true,
  }) async {
    try {
      await _locationService.stop();
      _isTracking = false;
      _waitingInitialFix = false;
      _scheduleEnforcer?.cancel();
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Modo nativo exclusivo en Android: detiene nativo y desmarca fg_tracking_active][obj: TrackingController.stopTracking native_exclusive]
      if (_nativeAlwaysOn && defaultTargetPlatform == TargetPlatform.android) {
        if (stopNativeTracking) {
          await BackgroundScheduleManager.stopNativeTracking();
          unawaited(
            GetIt.I<TelemetryLogService>().log(
              'Tracking nativo exclusivo: fin (modo_real=Nativo)',
            ),
          );
        }
        if (markForegroundTrackingInactive) {
          await BackgroundScheduleManager.setForegroundTrackingActive(false);
        }
        notifyListeners();
        return;
      }
      unawaited(
        GetIt.I<TelemetryLogService>()
            .log('Tracking Flutter: fin (modo_real=Flutter)'),
      );
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Desmarca tracking foreground para permitir que Android use servicio nativo si corresponde por horario][obj: TrackingController.stopTracking fg_tracking_active]
      if (markForegroundTrackingInactive) {
        await BackgroundScheduleManager.setForegroundTrackingActive(false);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error deteniendo tracking: $e');
    }
  }

  // Adaptive Tracking State
  DateTime? _stationarySince;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-03 16:21 UTC-5 (Lima)][desc: Añade umbrales adaptativos (speed/accuracy/batería) y buffer de velocidad para estabilizar cambios de perfil][obj: TrackingController adaptive tracking constants]
  TrackingProfile _currentProfile = TrackingProfile.vehicle; // Start aggressive
  final List<double> _recentSpeeds = [];
  static const int _speedSampleSize = 5;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:42 UTC-5 (Lima)][desc: Relaja accuracy para decisión de perfil en ciudad][obj: TrackingController maxAccuracyForProfile]
  static const double _maxAccuracyMetersForProfile = 40.0;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:42 UTC-5 (Lima)][desc: Ajusta umbrales propuestos para ciudad (a pie/auto) + Kalman + minDistance/minTime][obj: TrackingController accuracy/jump filter]
  static const double _maxAccuracyMetersStill = 30.0;
  static const double _maxAccuracyMetersWalking = 40.0;
  static const double _maxAccuracyMetersVehicle = 80.0;
  static const int _defaultMaxStaleSeconds = 7200; // 2 horas
  int _maxStaleSeconds = _defaultMaxStaleSeconds;
  static const double _maxSpeedWalkingMps = 2.0; // ~7.2 km/h
  static const double _maxSpeedVehicleMps = 27.7777777778; // 100 km/h
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-20 08:05 UTC-5 (Lima)][desc: Endurece minTime/minDistance para reducir puntos demasiado cercanos][obj: TrackingController minTime/minDistance]
  int _minIntervalStillSeconds = 30;
  int _minIntervalWalkingSeconds = 5;
  int _minIntervalVehicleSeconds = 3;
  double _minDistanceStillMeters = 10.0;
  double _minDistanceWalkingMeters = 12.0;
  double _minDistanceVehicleMeters = 40.0;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-20 00:00 UTC-5 (Lima)][desc: Fuerza aceptar un punto si no llega ninguno por mucho tiempo (background/minimizado)][obj: TrackingController force accept]
  int _forceAcceptAfterSeconds = 300;
  int _captureIntervalSeconds = 10;
  int _captureDistanceMeters = 10;
  bool _nativeAlwaysOn = false;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 00:00 UTC-5 (Lima)][desc: Umbral fijo de accuracy configurable][obj: TrackingController accuracy threshold]
  double _maxAccuracyMeters = 20.0;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 00:00 UTC-5 (Lima)][desc: Toggle para activar/desactivar filtros en app][obj: TrackingController filters enabled]
  bool _filtersEnabled = false;
  static const double _maxJumpWalkingMeters = 120.0;
  static const double _maxJumpVehicleMeters = 500.0;
  static const int _maxJumpWindowSeconds = 10;
  static const int _maxKalmanGapSeconds = 60;
  static const double _defaultAccuracyMeters = 25.0;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-13 15:51 UTC-5 (Lima)][desc: Habilita tracking crítico solo dentro del horario laboral][obj: TrackingController critical mode]
  static const bool _alwaysCriticalTracking = false;

  LocationPoint? _lastAcceptedPoint;

  double? _refLat;
  double? _refLon;
  _Kalman1D? _kalmanX;
  _Kalman1D? _kalmanY;
  DateTime? _lastKalmanAt;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:45 UTC-5 (Lima)][desc: Expone la última decisión de filtro para diagnóstico en UI][obj: TrackingController lastFilterDecision]
  String? _lastFilterDecision;
  static const double _stillSpeedMps = 1.0;
  static const double _walkingSpeedMps = 2.5;
  static const int _stillMinutesThreshold = 3;
  static const int _lowBatteryThreshold = 20;
  int? _lastBatteryLevel;
  
  TrackingProfile get currentProfile => _currentProfile;
  String? get lastFilterDecision => _lastFilterDecision;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-20 00:00 UTC-5 (Lima)][desc: Expone y actualiza filtros configurables de tracking][obj: TrackingController tracking filter config]
  int get stillIntervalSeconds => _minIntervalStillSeconds;
  double get stillMinDistanceMeters => _minDistanceStillMeters;
  int get forceAcceptAfterSeconds => _forceAcceptAfterSeconds;
  double get maxAccuracyMeters => _maxAccuracyMeters;
  bool get filtersEnabled => _filtersEnabled;
  int get captureIntervalSeconds => _captureIntervalSeconds;
  int get captureDistanceMeters => _captureDistanceMeters;
  int get maxStaleSeconds => _maxStaleSeconds;
  bool get nativeAlwaysOn => _nativeAlwaysOn;

  Future<void> _loadTrackingFilterPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stillInterval = prefs.getInt('tracking_still_interval_s');
      final stillDistance = prefs.getDouble('tracking_still_min_dist_m');
      final forceAccept = prefs.getInt('tracking_force_accept_s');
      final maxAccuracy = prefs.getDouble('tracking_max_accuracy_m');
      final filtersEnabled = prefs.getBool('tracking_filters_enabled');
      final captureInterval = prefs.getInt('tracking_capture_interval_s');
      final captureDistance = prefs.getInt('tracking_capture_distance_m');
      final maxStale = prefs.getInt('tracking_max_stale_s');
      final nativeAlwaysOn = prefs.getBool('tracking_native_always_on');
      updateTrackingFilters(
        stillIntervalSeconds: stillInterval,
        stillMinDistanceMeters: stillDistance,
        forceAcceptSeconds: forceAccept,
        maxAccuracyMeters: maxAccuracy,
        filtersEnabled: filtersEnabled,
        captureIntervalSeconds: captureInterval,
        captureDistanceMeters: captureDistance,
        maxStaleSeconds: maxStale,
        nativeAlwaysOn: nativeAlwaysOn,
        notify: false,
      );
    } catch (_) {}
  }

  void updateTrackingFilters({
    int? stillIntervalSeconds,
    double? stillMinDistanceMeters,
    int? forceAcceptSeconds,
    double? maxAccuracyMeters,
    bool? filtersEnabled,
    int? captureIntervalSeconds,
    int? captureDistanceMeters,
    int? maxStaleSeconds,
    bool? nativeAlwaysOn,
    bool notify = true,
  }) {
    if (stillIntervalSeconds != null) {
      _minIntervalStillSeconds = stillIntervalSeconds.clamp(5, 600);
    }
    if (stillMinDistanceMeters != null) {
      _minDistanceStillMeters = stillMinDistanceMeters.clamp(1.0, 100.0);
    }
    if (forceAcceptSeconds != null) {
      _forceAcceptAfterSeconds = forceAcceptSeconds.clamp(10, 900);
    }
    if (maxAccuracyMeters != null) {
      _maxAccuracyMeters = maxAccuracyMeters.clamp(5.0, 100.0);
    }
    if (filtersEnabled != null) {
      _filtersEnabled = filtersEnabled;
    }
    if (captureIntervalSeconds != null) {
      _captureIntervalSeconds = captureIntervalSeconds.clamp(1, 120);
    }
    if (captureDistanceMeters != null) {
      _captureDistanceMeters = captureDistanceMeters.clamp(1, 100);
    }
    if (maxStaleSeconds != null) {
      _maxStaleSeconds = maxStaleSeconds.clamp(60, 43200);
    }
    if (nativeAlwaysOn != null) {
      _nativeAlwaysOn = nativeAlwaysOn;
    }
    if (notify) notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:10 UTC-5 (Lima)][desc: Procesa ubicación para tracking adaptativo y sincronización][obj: TrackingController.processLocationUpdate]
  Future<void> processLocationUpdate({
    required String firebaseUid,
    required LocationPoint point,
    int? batteryLevel,
    String? activityType,
  }) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-03 16:21 UTC-5 (Lima)][desc: Guarda último nivel de batería para adaptar precisión en modo quieto][obj: TrackingController.processLocationUpdate battery]
    _lastBatteryLevel = batteryLevel;
    _evaluateAdaptiveProfile(point);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Modo nativo exclusivo en Android: geolocator solo actualiza el mapa, el nativo encola los puntos][obj: TrackingController.processLocationUpdate native_exclusive]
    if (_nativeAlwaysOn && defaultTargetPlatform == TargetPlatform.android) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Telemetría: punto GPS recibido en modo nativo, capturado por servicio nativo no Flutter][obj: TrackingController.processLocationUpdate native_exclusive telemetry]
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          'Punto GPS (modo nativo): lat=${point.latitude.toStringAsFixed(6)} lng=${point.longitude.toStringAsFixed(6)} → servicio nativo (SQLite nativo)',
        ),
      );
      return;
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Usa cola local en lugar de envío directo][obj: TrackingController.processLocationUpdate]
    await _syncManager.queueLocation(
      firebaseUid: firebaseUid,
      point: point,
      batteryLevel: batteryLevel,
      activityType: activityType,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-03 16:21 UTC-5 (Lima)][desc: Evalúa perfil con filtros de precisión y promedio de velocidad para evitar ruido][obj: TrackingController._evaluateAdaptiveProfile]
  void _evaluateAdaptiveProfile(LocationPoint point) {
    // FILTRO: selección de perfil (still/walking/vehicle).
    // - Se ignora si tracking crítico está activo o si estamos dentro de horario fijo.
    // - Solo se usa si el punto es confiable para perfil (accuracy aceptable).
    // - Impacto: cambia settings de LocationService (frecuencia/distancia), no descarta puntos.
    if (_alwaysCriticalTracking || _isWithinScheduleNow()) return;
    if (!_isReliableForProfile(point)) return;

    final effectiveSpeed = _effectiveSpeedForProfile(point);
    _addSpeedSample(effectiveSpeed);
    final speed = _averageSpeed();
    TrackingProfile newProfile = _currentProfile;

    if (speed < _stillSpeedMps) {
      // Potential stationary
      if (_stationarySince == null) {
        _stationarySince = DateTime.now();
      } else if (DateTime.now().difference(_stationarySince!).inMinutes >=
          _stillMinutesThreshold) {
        newProfile = TrackingProfile.still;
      }
    } else {
      // Moving
      _stationarySince = null;
      if (speed < _walkingSpeedMps) {
        newProfile = TrackingProfile.walking;
      } else {
        newProfile = TrackingProfile.vehicle;
      }
    }

    // Immediate switch if upgrading (Still -> Walking/Vehicle) or switching between moving modes
    // Debounce only applies to entering Still mode (handled by _stationarySince check above)
    if (newProfile != _currentProfile) {
      // If we were Still and now moving, switch immediately.
      // If we were Moving and now Still, the 2 min delay already passed.
      _setProfile(newProfile, speed: speed, accuracy: point.accuracy);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-03 16:21 UTC-5 (Lima)][desc: Ajusta settings por perfil incluyendo degradación en batería baja y log detallado][obj: TrackingController._setProfile]
  void _setProfile(TrackingProfile profile, {double? speed, double? accuracy}) {
    if (_alwaysCriticalTracking || _isWithinScheduleNow()) return;
    logDebug(
      'Cambiando perfil de tracking: ${_currentProfile.name} -> ${profile.name}',
      details:
          'avgSpeed=${speed?.toStringAsFixed(2)} m/s, accuracy=${accuracy?.toStringAsFixed(1)} m, battery=$_lastBatteryLevel%',
    );
    _currentProfile = profile;
    LocationSettings settings;
    //creamos profiles para cuando la bateria está baja, para cuando esta en tura o en auto
    switch (profile) {
      case TrackingProfile.still:
        final lowBattery =
            _lastBatteryLevel != null && _lastBatteryLevel! <= _lowBatteryThreshold;
        settings = _buildLocationSettings(
          accuracy: LocationAccuracy.low,
          distanceFilter: 100,
          intervalSeconds: _captureIntervalSeconds,
        );
        if (!lowBattery) {
          settings = _buildLocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 100,
            intervalSeconds: _captureIntervalSeconds,
          );
        }
        break;
      case TrackingProfile.walking:
        settings = _buildLocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: _captureDistanceMeters,
          intervalSeconds: _captureIntervalSeconds,
        );
        break;
      case TrackingProfile.vehicle:
        settings = _buildLocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: _captureDistanceMeters,
          intervalSeconds: _captureIntervalSeconds,
        );
        break;
    }
    
    _locationService.updateSettings(settings);
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-03 16:21 UTC-5 (Lima)][desc: Descarta puntos con baja precisión para decisión de perfil][obj: TrackingController._isReliableForProfile]
  bool _isReliableForProfile(LocationPoint point) {
    // FILTRO: precision para decidir perfil.
    // - Si accuracy es mala, no se usa este punto para calcular perfil.
    // - Impacto: evita cambios de perfil basados en puntos ruidosos.
    final accuracy = point.accuracy;
    if (accuracy == null) return true;
    return accuracy <= _maxAccuracyMetersForProfile;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:42 UTC-5 (Lima)][desc: Si no hay speed, estima con accuracy + distancia al último punto][obj: TrackingController _effectiveSpeedForProfile]
  double _effectiveSpeedForProfile(LocationPoint point) {
    // FILTRO/HEURÍSTICA: velocidad efectiva para decidir perfil.
    // - Usa speed directo si existe.
    // - Si no, estima con distancia/tiempo, pero solo si accuracy no es muy mala.
    // - Impacto: mejora decisión de perfil sin introducir saltos falsos.
    final speed = point.speed;
    if (speed != null && speed > 0) return speed;
    final prev = _lastAcceptedPoint;
    if (prev == null) return 0.0;
    final acc = point.accuracy ?? _defaultAccuracyMeters;
    if (acc > _maxAccuracyMetersVehicle) {
      return 0.0;
    }
    final dt = point.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    if (dt <= 0) return 0.0;
    final dist = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      point.latitude,
      point.longitude,
    );
    return dist / dt;
  }

  bool _isWithinScheduleNow() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final start = _trackingStartHour ?? 8;
    final end = _trackingEndHour ?? 20;
    final hour = now.hour;
    return hour >= start && hour < end;
  }

  LocationSettings _criticalLocationSettings() {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 10:45 UTC-5 (Lima)][desc: Usa intervalo/distancia configurables en modo crítico][obj: TrackingController._criticalLocationSettings configurable]
    return _buildLocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: _captureDistanceMeters,
      intervalSeconds: _captureIntervalSeconds,
    );
  }

  LocationSettings _captureSettings() {
    return _buildLocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: _captureDistanceMeters,
      intervalSeconds: _captureIntervalSeconds,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:51 UTC-5 (Lima)][desc: Agrega rama iOS con AppleSettings (allowBackgroundLocationUpdates, pauseLocationUpdatesAutomatically=false)][obj: TrackingController._buildLocationSettings iOS]
  LocationSettings _buildLocationSettings({
    required LocationAccuracy accuracy,
    required int distanceFilter,
    int? intervalSeconds,
  }) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: Duration(seconds: intervalSeconds ?? 10),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
      );
    }
    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-03 16:21 UTC-5 (Lima)][desc: Mantiene ventana de velocidad para suavizar decisión de movimiento][obj: TrackingController._addSpeedSample]
  void _addSpeedSample(double speed) {
    _recentSpeeds.add(speed);
    if (_recentSpeeds.length > _speedSampleSize) {
      _recentSpeeds.removeAt(0);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-03 16:21 UTC-5 (Lima)][desc: Calcula velocidad promedio de la ventana][obj: TrackingController._averageSpeed]
  double _averageSpeed() {
    if (_recentSpeeds.isEmpty) return 0.0;
    final total = _recentSpeeds.fold<double>(0.0, (sum, v) => sum + v);
    return total / _recentSpeeds.length;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:49 UTC-5 (Lima)][desc: Intenta enviar ubicaciones pendientes][obj: TrackingController.tryFlushPending]
  Future<void> tryFlushPending({required String firebaseUid}) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Flush por usuario para no enviar ubicaciones de otro login][obj: TrackingController.tryFlushPending uid]
    await _syncManager.flushPending(firebaseUid: firebaseUid);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:50 UTC-5 (Lima)][desc: Valida si está dentro del horario permitido][obj: TrackingController.isWithinSchedule]
  bool isWithinSchedule() {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 18:36 UTC-5 (Lima)][desc: Restringe tracking a días hábiles (L-V)][obj: TrackingController.isWithinSchedule weekday guard]
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final start = _trackingStartHour ?? 8;
    final end = _trackingEndHour ?? 20;
    final hour = now.hour;
    return hour >= start && hour < end;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-09 15:04 UTC-5 (Lima)][desc: Filtra puntos crudos para mapa y persistencia; descarta saltos y ubicaciones antiguas][obj: TrackingController.filterPoint]
  LocationPoint? filterPoint(LocationPoint point) {
    final filtered = _applyKalmanFilter(point);
    if (!_filtersEnabled) {
      _lastFilterDecision = 'OK: filtros desactivados';
      return filtered;
    }
    if (!_shouldAcceptPoint(filtered, rawPoint: point)) {
      return null;
    }
    _lastAcceptedPoint = filtered;
    return filtered;
  }


  void _logDiscard(String regla, String details) {
    unawaited(
      GetIt.I<TelemetryLogService>().log(
        'Descartado punto: regla=$regla detalles=$details',
      ),
    );
  }

  bool _shouldAcceptPoint(LocationPoint point, {LocationPoint? rawPoint}) {
    // Orden de aplicación de reglas (app):
    // 1) same_lat_lng_same_timestamp
    // 2) precision
    // 3) timestamp_no_creciente
    // 4) same_lat_lng_<10s
    // 5) min_dist_min_time
    // 6) force_accept (señal de vida, dt>=300s)
    // 7) salto_velocidad
    // 8) salto_ventana_corta
    // 9) antiguedad (puntos muy antiguos)

    final accuracy = point.accuracy ?? rawPoint?.accuracy;
    final prev = _lastAcceptedPoint;
    if (prev == null) {
      final speedForAccuracy = point.speed ?? 0.0;
      final maxAllowedAccuracy = _maxAccuracyForSpeed(speedForAccuracy);
      // Regla 2: precision. Accuracy > max -> RECHAZA.
      // Ejemplo: accuracy=50m y max=20m -> RECHAZA.
      if (accuracy != null && accuracy > maxAllowedAccuracy) {
        _lastFilterDecision =
            'REJ: acc ${accuracy.toStringAsFixed(1)}m > ${maxAllowedAccuracy.toStringAsFixed(1)}m';
        logDebug(
          'Punto descartado por baja precisión',
          details:
              'accuracy=${accuracy.toStringAsFixed(1)}m max=${maxAllowedAccuracy.toStringAsFixed(1)}m speed=${speedForAccuracy.toStringAsFixed(2)}',
        );
        _logDiscard(
          'precision',
          'accuracy=${accuracy.toStringAsFixed(1)}m max=${maxAllowedAccuracy.toStringAsFixed(1)}m',
        );
        return false;
      }
    } else {
      final dt = point.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
      final sameInstant =
          point.timestamp.millisecondsSinceEpoch ==
          prev.timestamp.millisecondsSinceEpoch;
      // Regla 1: duplicado exacto (misma lat/lng + mismo timestamp con ms) -> RECHAZA.
      // Ejemplo: mismo punto reenviado por reintento con ts idéntico -> RECHAZA.
      if (point.latitude == prev.latitude &&
          point.longitude == prev.longitude &&
          sameInstant) {
        _lastFilterDecision = 'REJ: same lat/lng same instant';
        logDebug(
          'Punto descartado por misma lat/lng y mismo timestamp',
          details:
              'ts=${point.timestamp.toIso8601String()} prev=${prev.timestamp.toIso8601String()}',
        );
        _logDiscard(
          'misma_lat_lng_mismo_timestamp',
          'ts=${point.timestamp.toIso8601String()} prev=${prev.timestamp.toIso8601String()}',
        );
        return false;
      }
      final speedForAccuracy = point.speed ?? (dt > 0 ? Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        point.latitude,
        point.longitude,
      ) / dt : 0.0);
      final maxAllowedAccuracy = _maxAccuracyForSpeed(speedForAccuracy);
      // Regla 2: precision. Accuracy > max -> RECHAZA.
      // Ejemplo: accuracy=30m andando a pie (max 25m) -> RECHAZA.
      if (accuracy != null && accuracy > maxAllowedAccuracy) {
        _lastFilterDecision =
            'REJ: acc ${accuracy.toStringAsFixed(1)}m > ${maxAllowedAccuracy.toStringAsFixed(1)}m';
        logDebug(
          'Punto descartado por baja precisión',
          details:
              'accuracy=${accuracy.toStringAsFixed(1)}m max=${maxAllowedAccuracy.toStringAsFixed(1)}m speed=${speedForAccuracy.toStringAsFixed(2)}',
        );
        _logDiscard(
          'precision',
          'accuracy=${accuracy.toStringAsFixed(1)}m max=${maxAllowedAccuracy.toStringAsFixed(1)}m',
        );
        return false;
      }
      // Regla 3: timestamp no creciente (dt <= 0) implica dato inválido -> RECHAZA.
      // Ejemplo: llega un punto con hora anterior al último aceptado -> RECHAZA.
      if (dt <= 0) {
        _lastFilterDecision = 'REJ: ts<=0';
        logDebug('Punto descartado por timestamp no creciente');
        _logDiscard('timestamp_no_creciente', 'dt=${dt.toStringAsFixed(1)}s');
        return false;
      }
      // Regla 4: misma lat/lng en menos de 10s se considera ruido/repetido -> RECHAZA.
      // Ejemplo: dt=6s, lat/lng igual al anterior -> RECHAZA.
      if (point.latitude == prev.latitude &&
          point.longitude == prev.longitude &&
          dt < 10.0) {
        _lastFilterDecision = 'REJ: same lat/lng <10s';
        logDebug(
          'Punto descartado por misma lat/lng en ventana corta',
          details: 'dt=${dt.toStringAsFixed(1)}s',
        );
        _logDiscard(
          'misma_lat_lng_<10s',
          'dt=${dt.toStringAsFixed(1)}s',
        );
        return false;
      }
      final dist = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        point.latitude,
        point.longitude,
      );
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-17 00:00 UTC-5 (Lima)][desc: Homologa con backend: speed=0 no significa detenido, usa dist/dt como fallback igual que cuando speed=null][obj: TrackingController._shouldAcceptPoint derivedSpeed]
      final derivedSpeed = (point.speed != null && point.speed! > 0)
          ? point.speed!
          : (dist / dt);
      final minInterval = _minIntervalSecondsForSpeed(derivedSpeed);
      final minDistance = _minDistanceMetersForSpeed(derivedSpeed);
      // Regla 5: min_dist_min_time. Movimiento muy corto en poco tiempo -> RECHAZA.
      // Ejemplo: dt=4s y dist=5m (caminando) -> RECHAZA.
      if (dt < minInterval && dist < minDistance) {
        _lastFilterDecision =
            'REJ: min ${dist.toStringAsFixed(1)}m/${dt.toStringAsFixed(1)}s';
        logDebug(
          'Punto descartado por minDistance/minTime',
          details:
              'dist=${dist.toStringAsFixed(1)}m < $minDistance, dt=${dt.toStringAsFixed(1)}s < $minInterval',
        );
        _logDiscard(
          'min_dist_min_time',
          'dist=${dist.toStringAsFixed(1)}m < $minDistance, dt=${dt.toStringAsFixed(1)}s < $minInterval',
        );
        return false;
      }
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-17 00:00 UTC-5 (Lima)][desc: Mueve force_accept ANTES de salto_velocidad y salto_ventana_corta. Si dt>=300s se acepta como señal de vida sin importar la velocidad implícita (el gap largo hace inválida la comparación de velocidad).][obj: TrackingController._shouldAcceptPoint force_accept order]
      // Regla 6: force-accept (señal de vida). Si dt >= 300s, acepta sin verificar velocidad.
      if (dt >= _forceAcceptAfterSeconds) {
        _lastFilterDecision = 'OK: force ${dt.toStringAsFixed(0)}s';
        return true;
      }
      final impliedSpeed = dist / dt;
      // Regla 7: salto_velocidad. Velocidad implícita irreal -> RECHAZA.
      // Ejemplo: dist=900m, dt=5s -> 180 m/s (irreal) -> RECHAZA.
      if (impliedSpeed > _maxSpeedForSpeed(derivedSpeed)) {
        _lastFilterDecision =
            'REJ: speed ${impliedSpeed.toStringAsFixed(1)}m/s';
        logDebug(
          'Punto descartado por salto',
          details:
              'dist=${dist.toStringAsFixed(1)}m dt=${dt.toStringAsFixed(1)}s speed=${impliedSpeed.toStringAsFixed(1)}m/s',
        );
        _logDiscard(
          'salto_velocidad',
          'dist=${dist.toStringAsFixed(1)}m dt=${dt.toStringAsFixed(1)}s speed=${impliedSpeed.toStringAsFixed(1)}m/s',
        );
        return false;
      }
      // Regla 8: salto_ventana_corta. Salto grande en pocos segundos -> RECHAZA.
      // Ejemplo: dist=300m en 5s (ventana corta) -> RECHAZA.
      if (dt <= _maxJumpWindowSeconds) {
        final maxJump = _maxJumpMetersForSpeed(derivedSpeed);
        if (dist > maxJump) {
          _lastFilterDecision =
              'REJ: jump ${dist.toStringAsFixed(1)}m/${dt.toStringAsFixed(1)}s';
          logDebug(
            'Punto descartado por salto (ventana corta)',
            details:
                'dist=${dist.toStringAsFixed(1)}m max=$maxJump dt=${dt.toStringAsFixed(1)}s',
          );
          _logDiscard(
            'salto_ventana_corta',
            'dist=${dist.toStringAsFixed(1)}m max=$maxJump dt=${dt.toStringAsFixed(1)}s',
          );
          return false;
        }
      }
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-17 00:00 UTC-5 (Lima)][desc: Homologa con backend: antigüedad usa dt (gap desde último aceptado) en lugar de age (edad vs. ahora). _allowNextStalePoint eliminado, cubierto por force_accept.][obj: TrackingController._shouldAcceptPoint antiguedad]
      // Regla 9: antiguedad. Si el gap desde el último aceptado es muy grande, se descarta.
      if (dt > _maxStaleSeconds) {
        _lastFilterDecision = 'REJ: antiguedad ${dt.toStringAsFixed(0)}s';
        logDebug(
          'Punto descartado por antigüedad',
          details: 'dt=${dt.toStringAsFixed(0)}s',
        );
        _logDiscard('antiguedad', 'dt=${dt.toStringAsFixed(0)}s');
        return false;
      }
    }

    _lastFilterDecision = 'OK';
    return true;
  }

  double _maxAccuracyForSpeed(double speed) {
    if (speed <= 1.0) return 20.0; // Detenido / Caminando lento (0-3.6 km/h)
    if (speed <= 5.0) return 25.0; // Caminando / Bici (3-18 km/h)
    if (speed <= 15.0) return 35.0; // Tráfico urbano (18-54 km/h)
    return 50.0; // Carretera (54+ km/h)
  }

  double _maxSpeedForSpeed(double speed) {
    if (speed < _walkingSpeedMps) return _maxSpeedWalkingMps;
    return _maxSpeedVehicleMps;
  }

  double _maxJumpMetersForSpeed(double speed) {
    if (speed < _walkingSpeedMps) return _maxJumpWalkingMeters;
    return _maxJumpVehicleMeters;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:30 UTC-5 (Lima)][desc: Aplica minTime/minDistance por perfil para reducir ruido GPS][obj: TrackingController minTime/minDistance helpers]
  int _minIntervalSecondsForSpeed(double speed) {
    if (speed <= _stillSpeedMps) return _minIntervalStillSeconds;
    if (speed < _walkingSpeedMps) return _minIntervalWalkingSeconds;
    return _minIntervalVehicleSeconds;
  }

  double _minDistanceMetersForSpeed(double speed) {
    if (speed <= _stillSpeedMps) return _minDistanceStillMeters;
    if (speed < _walkingSpeedMps) return _minDistanceWalkingMeters;
    return _minDistanceVehicleMeters;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:30 UTC-5 (Lima)][desc: Suaviza lat/lon con Kalman 2D simple (en metros) para reducir jitter][obj: TrackingController _applyKalmanFilter]
  LocationPoint _applyKalmanFilter(LocationPoint point) {
    // FILTRO: Kalman 2D (suavizado).
    // - Reduce jitter de GPS.
    // - No descarta puntos; solo ajusta lat/lng.
    // - Si no hay estado previo o hay gaps grandes, reinicia el filtro.
    final accuracy = point.accuracy ?? _defaultAccuracyMeters;
    if (_refLat == null || _refLon == null || _kalmanX == null || _kalmanY == null) {
      _resetKalman(point, accuracy);
      return point;
    }
    final lastAt = _lastKalmanAt;
    final dt =
        lastAt == null ? 0.0 : point.timestamp.difference(lastAt).inMilliseconds / 1000.0;
    if (dt <= 0 || dt > _maxKalmanGapSeconds) {
      _resetKalman(point, accuracy);
      return point;
    }
    final metersPerDegLat = 111320.0;
    final metersPerDegLon = metersPerDegLat * math.cos((_refLat! * math.pi) / 180.0);
    final x = (point.longitude - _refLon!) * metersPerDegLon;
    final y = (point.latitude - _refLat!) * metersPerDegLat;
    final filteredX = _kalmanX!.update(x, accuracy, dt);
    final filteredY = _kalmanY!.update(y, accuracy, dt);
    final filteredLat = _refLat! + (filteredY / metersPerDegLat);
    final filteredLon = _refLon! + (filteredX / metersPerDegLon);
    _lastKalmanAt = point.timestamp;
    return LocationPoint(
      latitude: filteredLat,
      longitude: filteredLon,
      timestamp: point.timestamp,
      accuracy: point.accuracy,
      altitude: point.altitude,
      speed: point.speed,
      heading: point.heading,
    );
  }

  void _resetKalman(LocationPoint point, double accuracy) {
    _refLat = point.latitude;
    _refLon = point.longitude;
    _kalmanX = _Kalman1D();
    _kalmanY = _Kalman1D();
    _kalmanX!.reset(0.0, accuracy);
    _kalmanY!.reset(0.0, accuracy);
    _lastKalmanAt = point.timestamp;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:50 UTC-5 (Lima)][desc: Actualiza horario de tracking][obj: TrackingController.updateSchedule]
  void updateSchedule({int? startHour, int? endHour}) {
    if (startHour != null) _trackingStartHour = startHour;
    if (endHour != null) _trackingEndHour = endHour;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:51 UTC-5 (Lima)][desc: Resetea flag de manejo de horario][obj: TrackingController.resetScheduleHandled]
  void resetScheduleHandled() {
    _outsideScheduleHandled = false;
    notifyListeners();
  }

  void setWaitingInitialFix(bool value) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 17:10 UTC (Lima)][desc: Ajusta flag de espera de primer fix][obj: TrackingController.setWaitingInitialFix]
    _waitingInitialFix = value;
    notifyListeners();
  }

  void _rescheduleScheduleEnforcer(Function() onOutsideSchedule) {
    _scheduleEnforcer?.cancel();
    if (!_isTracking) return;
    
    final start = _trackingStartHour ?? 8;
    final end = _trackingEndHour ?? 20;
    
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day, end);
    final duration = endDate.difference(now);
    if (duration.isNegative || duration.inSeconds == 0) {
      onOutsideSchedule();
    } else {
      _scheduleEnforcer = Timer(duration, onOutsideSchedule);
    }
  }
}

enum TrackingProfile { still, walking, vehicle }

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:30 UTC-5 (Lima)][desc: Implementa Kalman 1D reutilizable para suavizado de coordenadas][obj: TrackingController _Kalman1D]

class _Kalman1D {
  double _x = 0.0;
  double _p = 1.0;
  bool _initialized = false;
  static const double _processNoise = 1.0;

  void reset(double measurement, double accuracy) {
    _x = measurement;
    _p = accuracy * accuracy;
    _initialized = true;
  }

  double update(double measurement, double accuracy, double dt) {
    if (!_initialized) {
      reset(measurement, accuracy);
      return _x;
    }
    final q = _processNoise * dt;
    _p += q;
    final r = accuracy * accuracy;
    final k = _p / (_p + r);
    _x = _x + k * (measurement - _x);
    _p = (1 - k) * _p;
    return _x;
  }
}
