// [RESTORED][autor: claude][fecha: 2025-12-05][desc: Archivo restaurado agregando variables faltantes del refactoring]
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/visit_plan.dart';
import 'package:get_it/get_it.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/identity_service.dart';
import '../../services/location_service.dart';
import '../../services/telemetry_log_service.dart';
import '../../services/screen_state_service.dart';
import '../../services/location_sync_manager.dart';
import '../../services/pending_location_store.dart';
import '../../services/background_schedule_manager.dart';
import '../../services/mapbox_service.dart';
import '../../services/native_navigation_service.dart';
import '../../services/offline_sync_status.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../utils/logger.dart';
import '../../config/feature_flags.dart';
import '../auth/auth_gate.dart';

import 'controllers/map_screen_controller.dart';
import 'controllers/visit_controller.dart';
import 'controllers/tracking_controller.dart';
import 'controllers/route_controller.dart';
import 'controllers/map_initialization_service.dart';
import 'controllers/auth_flow_controller.dart';
import 'controllers/visit_flow_controller.dart';
import 'controllers/route_flow_controller.dart';
import 'controllers/history_flow_controller.dart';
import 'controllers/guidance_flow_controller.dart';
import 'controllers/app_lifecycle_manager.dart';
import 'controllers/location_flow_controller.dart';
import 'controllers/map_timer_manager.dart';
import 'controllers/sync_state_controller.dart';
import 'map_view_model.dart';

import 'widgets/map_app_bar.dart';
import 'widgets/dialogs/map_dialogs.dart';
import 'widgets/map_wrapper.dart';
import 'widgets/sheets/map_settings_sheet.dart';
import 'widgets/dialogs/map_layers_dialog.dart';
import 'widgets/map_overlay_layer.dart';
import 'utils/map_camera_utils.dart';
import 'utils/map_render_utils.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // Access through get_it to keep screen clean
  LocationService get _locationService => GetIt.I<LocationService>();
  ApiService get _apiService => GetIt.I<ApiService>();
  LocationSyncManager get _syncManager => GetIt.I<LocationSyncManager>();
  
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:30 UTC-5 (Lima)][desc: Guarda instancia MapboxMap cuando se usa mapa nativo para controlar cámara/zoom sin depender de FlutterMap][obj: MapScreen._nativeMap]
  mb.MapboxMap? _nativeMap;

  // ViewModels - Provistos por context.read
  late final MapScreenController _stateController;
  late final VisitController _visitController;
  late final TrackingController _trackingController;
  late final RouteController _routeController;

  // Manager Modules locales
  late final AuthFlowController _authFlowController;
  late final AppLifecycleManager _lifecycleManager;
  late final MapInitializationService _mapInitService;
  late final GuidanceFlowController _guidanceFlowController;
  late final VisitFlowController _visitFlowController;
  late final RouteFlowController _routeFlowController;
  late final LocationFlowController _locationFlowController;
  late final SyncStateController _syncStateController;
  late final MapTimerManager _timerManager;

  final MapController _mapController = MapController();
  HistoryFlowController? get _historyFlowController => GetIt.I.isRegistered<HistoryFlowController>() ? GetIt.I<HistoryFlowController>() : null;

  int get _trackingStartHour => _trackingController.trackingStartHour;
  int get _trackingEndHour => _trackingController.trackingEndHour;

  static const bool _enforceEndHour = false;

  String? _firebaseUid;
  bool _shouldResumeTracking = false;
  StreamSubscription<String>? _screenStateSub;
  bool _isInForeground = true;
  final OfflineSyncStatus _syncStatus = GetIt.I<OfflineSyncStatus>();
  static const MethodChannel _arrivalAlertChannel =
      MethodChannel('pe.gob.onp.thaqhiri/arrival_alert');
  static const MethodChannel _trackingModeChannel =
      MethodChannel('pe.gob.onp.thaqhiri/tracking_mode_notify');

  // Getters locales puente de UI
  bool get _isTracking => _trackingController.isTracking;
  // Workarounds
  static const bool _showLocationMarker = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScreenStateService.instance.start();
    _screenStateSub = ScreenStateService.instance.stream.listen((event) {
      if (event == 'screen_off') {
        _handleScreenOff();
      } else if (event == 'screen_on') {
        _handleScreenOn();
      }
    });
    logDebug('MapScreen initState: registrando controladores en sub-scope de get_it');

    _stateController = context.read<MapScreenController>();
    _visitController = context.read<VisitController>();
    _trackingController = context.read<TrackingController>();
    _routeController = context.read<RouteController>();
    _syncStateController = SyncStateController();
    _timerManager = MapTimerManager();

    _initControllers();
    _initSubscriptionsAndTimers();
  }

  // Construye e inicializa los 6 manager-controllers locales.
  void _initControllers() {
    _authFlowController = AuthFlowController(
      authService: GetIt.I<AuthService>(),
      identityService: GetIt.I<IdentityService>(),
      locationService: GetIt.I<LocationService>(),
      apiService: GetIt.I<ApiService>(),
      stateController: _stateController,
      trackingController: _trackingController,
      onLogoutSuccess: () {
        _visitController.reset();
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Limpia ruta, puntos pendientes y lastFix al cerrar sesión para evitar que el siguiente usuario vea datos del anterior][obj: MapScreen.onLogoutSuccess resetForNewSession]
        _stateController.resetForNewSession();
        _routeController.reset();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (_) => false,
          );
        }
      },
    );

    _mapInitService = MapInitializationService(
      stateController: _stateController,
      trackingController: _trackingController,
      visitController: _visitController,
      routeController: _routeController,
      apiService: GetIt.I<ApiService>(),
      locationService: GetIt.I<LocationService>(),
      syncManager: GetIt.I<LocationSyncManager>(),
    );

    _locationFlowController = LocationFlowController(
      apiService: GetIt.I<ApiService>(),
      locationService: GetIt.I<LocationService>(),
      syncManager: GetIt.I<LocationSyncManager>(),
      pendingLocationStore: PendingLocationStore(),
      trackingController: _trackingController,
      stateController: _stateController,
      visitController: _visitController,
      getFirebaseUid: () => _firebaseUid ?? GetIt.I<IdentityService>().uid,
      onLoadBgFlushInfo: _syncStateController.loadBgFlushInfo,
      onMoveCamera: _moveCameraTo,
      onArrivalDetected: _notifyArrivalDetected,
      onPromptArrivalConfirmation: _promptArrivalConfirmation,
      onMovedBeyondRadius: _onMovedBeyondRadius,
    );

    _guidanceFlowController = GuidanceFlowController(
      visitController: _visitController,
      routeController: _routeController,
      trackingController: _trackingController,
      stateController: _stateController,
      apiService: GetIt.I<ApiService>(),
      onPromptArrivalConfirmation: _promptArrivalConfirmation,
      onError: _showError,
      onSnack: _showSnack,
      onOutsideSchedule: _handleOutsideTrackingHours,
      getEnforceEndHour: () => _enforceEndHour,
      onPendingRouteCalculated: (dest, mode) => _locationFlowController
          .setPendingRouteRequest(
            destination: dest,
            mode: mode,
            drawOptimalRoute: true,
          ),
    );
    _locationFlowController.setDrawPendingRouteHandler(
      (current, destination, mode) => _guidanceFlowController.drawOptimalRouteFrom(
        current: current,
        destination: destination,
        mode: mode,
      ),
    );

    _routeFlowController = RouteFlowController(
      routeController: _routeController,
      visitController: _visitController,
      mapboxService: GetIt.I<MapboxService>(),
      stateController: _stateController,
      onArrivalMonitoring: _locationFlowController.handleArrivalMonitoring,
      onMoveCamera: _moveCameraTo,
    );

    _visitFlowController = VisitFlowController(
      visitController: _visitController,
      routeController: _routeController,
      stateController: _stateController,
      apiService: GetIt.I<ApiService>(),
      getFirebaseUid: () => _firebaseUid ?? GetIt.I<IdentityService>().uid,
      onProposeAlternatives: (visits) {
        if (!mounted) return;
        _routeFlowController.proposeInitialAlternatives(
          context,
          visits,
          _stateController.center,
        );
      },
      onFlushPendingLocations: () async {
        final uid = _firebaseUid ?? GetIt.I<IdentityService>().uid;
        if (uid == null || uid.isEmpty) return;
        await _syncManager.flushPending(firebaseUid: uid);
      },
      onPlanNextVisitRequested: (visit) async {
        if (!mounted) return;
        await _guidanceFlowController.startGuidanceFromPlanVisit(
          context,
          visit,
          _isInsideArrivalZoneNow(),
        );
      },
      getWaitingInitialFix: () => _trackingController.waitingInitialFix,
      onStartVisitReminder: _startVisitReminder,
      onStopVisitReminder: _stopVisitReminder,
      onStartGuidanceFromPlanVisit: (ctx, visit, isInside) =>
          _guidanceFlowController.startGuidanceFromPlanVisit(ctx, visit, isInside),
      onRefreshUI: () { if (mounted) setState(() {}); },
    );

    _lifecycleManager = AppLifecycleManager(
      trackingController: _trackingController,
      stateController: _stateController,
      apiService: GetIt.I<ApiService>(),
      onStartBackgroundFlushTimer: _startBackgroundFlushTimer,
      onStopBackgroundFlushTimer: _stopBackgroundFlushTimer,
      onStartTokenRefreshTimer: _startTokenRefreshTimer,
      onHydrateRouteFromBackground: _locationFlowController.hydrateRouteFromBackground,
      onRefreshPendingRouteFromLocal: _refreshPendingRouteFromLocal,
      onNotifyTrackingModeSwitch: _notifyTrackingModeSwitch,
      onError: _showError,
      onOutsideSchedule: _handleOutsideTrackingHours,
      getEnforceEndHour: () => _enforceEndHour,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Chequeo inmediato de llegada al volver al foreground usando última posición conocida][obj: MapScreen._lifecycleManager onCheckArrivalOnResume]
      onCheckArrivalOnResume: () async {
        final target = _visitController.currentTarget;
        if (target == null) return;
        final active = _visitController.activePlanVisit;
        if (active == null || active.state != VisitItemState.enRoute) return;
        if (_visitController.arrivalConfirmed) return;
        _locationFlowController.handleArrivalMonitoring(_stateController.center);
      },
    );
  }

  // Adjunta listeners, registra timers y suscripción al stream de ubicación.
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 10:13 UTC-5 (Lima)][desc: Observa lifecycle para alternar tracking foreground/background][obj: MapScreen.initState lifecycle observer]
  void _initSubscriptionsAndTimers() {
    _lifecycleManager.attach();
    _syncStatus.addListener(_onSyncStatusChanged);

    logDebug('MapScreen scope inicializado, prosiguiendo configuración local');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stateController.setTrackingState(
        isTracking: _trackingController.isTracking,
        waitingInitialFix: _trackingController.waitingInitialFix,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });

    _timerManager.startPendingRouteRefresh(_refreshPendingRouteFromLocal);
    _timerManager.startPendingSyncRefresh(_refreshPendingSyncIds);
    _locationFlowController.attachLocationStream();
    unawaited(_refreshPendingSyncIds());
    _startTokenRefreshTimer();
  }

  Future<void> _refreshPendingRouteFromLocal() async {
    await _locationFlowController.refreshPendingRouteFromLocal();
    if (mounted) setState(() {});
  }

  Future<void> _refreshPendingLocalCount() async {
    await _locationFlowController.refreshPendingLocalCount();
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    logDebug('MapScreen _bootstrap llamado');
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 00:00 UTC-5 (Lima)][desc: Resetea flag de llegada al iniciar sesión para re-disparar modal si corresponde][obj: MapScreen._bootstrap reset arrival zone]
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _visitController.resetArrivalZoneFlag();
    });
    void safeSetConnectionMessage(String? msg) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setConnectionMessage(msg);
      });
    }

    void safeSetShutdownMessage(String? msg) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _stateController.setShutdownMessage(msg);
      });
    }

    try {
      final backendOk = await _apiService.checkBackendAvailable(
        timeout: const Duration(seconds: 3),
      );
      if (!backendOk) {
        safeSetConnectionMessage('Mostrando mapa sin conexión.');
      }
    } catch (_) {}

    await _mapInitService.bootstrap(
      context: context,
      onConnectionMessage: safeSetConnectionMessage,
      onShutdownMessage: safeSetShutdownMessage,
      onError: _showError,
      onMoveCamera: _moveCameraTo,
      onOutsideSchedule: _handleOutsideTrackingHours,
      enforceEndHour: _enforceEndHour,
      showSchedulePrompt: false,
      onShowSchedulePrompt: () {
        _maybeShowSchedulePrompt();
      },
    );

    if (mounted) {
      final identity = GetIt.I<IdentityService>();
      setState(() {
        _firebaseUid = identity.uid;

        if (_firebaseUid != null) {
          if (!GetIt.I.isRegistered<HistoryFlowController>()) {
            GetIt.I.registerLazySingleton(() => HistoryFlowController(
              stateController: _stateController,
              apiService: _apiService,
              onError: _showError,
              firebaseUid: _firebaseUid!,
            ));
          }
        }
      });
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:30 UTC-5 (Lima)][desc: Al cargar mapa, pinta ruta pendiente desde DB local si existe][obj: MapScreen._bootstrap pendingRoute]
    await _refreshPendingRouteFromLocal();
    await _restoreActivePlanVisitFromServer();
    logDebug('MapScreen _bootstrap completado');
  }

  Future<void> _restoreActivePlanVisitFromServer() async {
    try {
      final plan = await _apiService.fetchVisitPlanForMe();
      VisitItem? inVisit;
      VisitItem? enRoute;
      for (final item in plan.items) {
        if (item.state == VisitItemState.inVisit) {
          inVisit = item;
          break;
        }
        if (item.state == VisitItemState.enRoute && enRoute == null) {
          enRoute = item;
        }
      }
      if (inVisit != null && mounted) {
        _visitController.setActivePlanVisit(inVisit);
        setState(() {});
      } else if (enRoute != null && mounted) {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Restaura target de llegada al reiniciar el app con visita EN_ROUTE activa; sin esto currentTarget queda null y arrival monitoring no corre][obj: MapScreen._restoreActivePlanVisitFromServer enRoute]
        _visitController.setActivePlanVisit(enRoute);
        final lat = enRoute.latitude;
        final lng = enRoute.longitude;
        if (lat != null && lng != null) {
          final target = LatLng(lat, lng);
          _visitController.setCurrentTarget(target);
          _visitController.resetArrivalState(target: target);
          unawaited(GetIt.I<TelemetryLogService>().log(
            'Restore: visita EN_ROUTE id=${enRoute.id} target restaurado lat=$lat lng=$lng',
          ));
        }
        setState(() {});
      }
    } catch (_) {}
  }

  bool _isInsideArrivalZoneNow() {
    final target = _visitController.currentTarget;
    if (target == null) return false;
    final d = Distance().as(LengthUnit.Meter, _stateController.center, target);
    return d <= _visitController.arrivalRadiusMeters;
  }


  Future<void> _refreshPendingSyncIds() async {
    try {
      await _syncStateController.refreshPendingSyncIds();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _onSyncStatusChanged() {
    if (!mounted) return;
    if (_syncStateController.shouldShowSyncCompletedToast(_syncStatus)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sincronización completada')),
      );
    }
    if (!_syncStatus.backendAvailable) {
      _setConnectionMessage('Mostrando mapa sin conexión.');
    } else if (_stateController.connectionMessage != null) {
      _setConnectionMessage(null);
    }
    unawaited(_refreshPendingLocalCount());
    setState(() {});
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 UTC-5 (Lima)][desc: Al apagar pantalla con app en foreground, delega tracking a nativo y loguea evento][obj: MapScreen._handleScreenOff]
  Future<void> _handleScreenOff() async {
    if (!_trackingController.isTracking) return;
    if (!_trackingController.nativeAlwaysOn) return;
    // Forzar delegación a nativo cuando la pantalla se apaga estando en primer plano.
    _shouldResumeTracking = true;
    _isInForeground = false;
    try {
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          'Pantalla apagada detectada: se detiene Flutter y se delega a Nativo',
        ),
      );
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 19:05 UTC-5 (Lima)][desc: En Android arranca nativo explícitamente antes de detener Flutter cuando la pantalla se apaga][obj: MapScreen._handleScreenOff robust native handoff]
      if (defaultTargetPlatform == TargetPlatform.android) {
        await BackgroundScheduleManager.setForegroundTrackingActive(false);
        await BackgroundScheduleManager.startNativeTracking();
      }
      await _trackingController.stopTracking(
        stopNativeTracking: false,
        markForegroundTrackingInactive: defaultTargetPlatform != TargetPlatform.android,
      );
      _stateController.setTrackingState(
        isTracking: _trackingController.isTracking,
        waitingInitialFix: _trackingController.waitingInitialFix,
      );
      await BackgroundScheduleManager.enforceNow();
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          'Pantalla apagada: delega tracking a Nativo (modo_real=Nativo)',
        ),
      );
    } catch (e) {
      logWarn(
        'No se pudo delegar a nativo al apagar pantalla',
        details: e.toString(),
      );
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          'Pantalla apagada: ERROR al delegar a Nativo',
        ),
      );
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 UTC-5 (Lima)][desc: Al encender pantalla, intenta reanudar tracking Flutter si fue delegado por screen-off][obj: MapScreen._handleScreenOn]
  Future<void> _handleScreenOn() async {
    if (!_shouldResumeTracking) return;
    _shouldResumeTracking = false;
    _isInForeground = true;
    try {
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          'Pantalla encendida detectada: intenta reanudar Flutter',
        ),
      );
      final ok = await _trackingController.startTracking(
        onError: _showError,
        onOutsideSchedule: _handleOutsideTrackingHours,
        enforceEndHour: _enforceEndHour,
      );
      _stateController.setTrackingState(
        isTracking: _trackingController.isTracking,
        waitingInitialFix: _trackingController.waitingInitialFix,
      );
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          ok
              ? 'Pantalla encendida: reanuda tracking Flutter (modo_real=Flutter)'
              : 'Pantalla encendida: no se pudo reanudar tracking Flutter',
        ),
      );
    } catch (e) {
      logWarn(
        'No se pudo reanudar tracking Flutter al encender pantalla',
        details: e.toString(),
      );
      unawaited(
        GetIt.I<TelemetryLogService>().log(
          'Pantalla encendida: ERROR al reanudar Flutter',
        ),
      );
    }
  }

  void _notifyArrivalDetected() {
    try {
      unawaited(
        GetIt.I<TelemetryLogService>()
            .log('Llegada detectada: primer_plano=$_isInForeground'),
      );
      if (_isInForeground) {
        HapticFeedback.heavyImpact();
        HapticFeedback.vibrate();
        SystemSound.play(SystemSoundType.alert);
      } else {
        unawaited(
          _arrivalAlertChannel.invokeMethod('notify').catchError((_) {}),
        );
      }
    } catch (_) {}
  }

  void _notifyTrackingModeSwitch(String modeHint) {
    try {
      final effective = _effectiveTrackingMode();
      unawaited(
        GetIt.I<TelemetryLogService>()
            .log('Modo real de tracking: $effective (evento: $modeHint)'),
      );
      if (_isInForeground) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tracking activo: $effective')),
        );
      }
      unawaited(
        _trackingModeChannel
            .invokeMethod('notify', {'mode': effective}).catchError((_) {}),
      );
    } catch (_) {}
  }

  String _effectiveTrackingMode() {
    if (_isInForeground) return 'Flutter';
    return 'Nativo';
  }

  Future<void> _promptArrivalConfirmation(LatLng current, VisitItem? item) async {
    await _visitFlowController.handleArrivalConfirmation(context, current, item);
  }

  Future<void> _onMovedBeyondRadius() async {
    await _visitFlowController.handleMovedBeyondRadius(context, _stateController.center);
  }

  void _startVerificationForCurrent() {
    _visitFlowController.startVerificationForCurrent(context);
  }

  void _startVisitReminder(VisitItem item) {
    final start = item.startTime ?? DateTime.now();
    _visitController.startVisitReminder(
      minutes: _visitController.visitReminderMinutes,
      onReminder: _showVisitReminderDialog,
      visit: item,
      startTime: start,
    );
  }

  void _stopVisitReminder() {
    _visitController.stopVisitReminder();
  }

  Future<void> _showVisitReminderDialog() async {
    if (!mounted) return;
    
    final action = await MapDialogs.showVisitReminderDialog(
      context, 
      _visitController.activeVisitStartedAt,
    );
    
    if (action == 'finish' && mounted) {
      final sure = await MapDialogs.showConfirmCloseVisitDialog(context);
      if (sure == true && mounted) {
        await _openVisitPlan();
      }
    }
  }

  Future<void> _openVisitPlan() => _visitFlowController.openVisitPlan(context);

  // Funciones de guiado y tracking extraídas a GuidanceFlowController
  
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  bool get _hasVisitInProgress =>
      _visitController.activePlanVisit != null &&
      _visitController.activePlanVisit!.state == VisitItemState.inVisit;

  Future<void> _attemptLogout() async {
    await _authFlowController.attemptLogout(
      context,
      hasVisitInProgress: _hasVisitInProgress,
    );
  }

  Future<void> _advanceToNextVisit() async {
    await _visitFlowController.advanceToNextVisit(context);
  }

  Future<void> _maybeShowSchedulePrompt() async {
    await _visitFlowController.maybeShowSchedulePrompt(context);
  }

  void _moveCameraTo(LatLng target) => MapCameraUtils.moveCameraTo(
        mapController: _mapController,
        nativeMap: _nativeMap,
        mapReady: _stateController.mapReady,
        target: target,
      );

  void _zoomBy(double delta) => MapCameraUtils.zoomBy(
        mapController: _mapController,
        nativeMap: _nativeMap,
        mapReady: _stateController.mapReady,
        delta: delta,
      );

  void _zoomIn() => _zoomBy(1.0);
  void _zoomOut() => _zoomBy(-1.0);

  Future<void> _startTracking({bool ensureBackend = true}) async {
    await _mapInitService.startTracking(
      ensureBackend: ensureBackend,
      onError: _showError,
      onOutsideSchedule: _handleOutsideTrackingHours,
      enforceEndHour: _enforceEndHour,
      context: context,
    );
  }

  Future<void> _stopTracking() async {
    if (!_isTracking) return;
    await _trackingController.stopTracking();

    if (!mounted) {
      _stateController.setTrackingState(
        isTracking: false,
        waitingInitialFix: false,
      );
      return;
    }

    _stateController.setTrackingState(
      isTracking: false,
      waitingInitialFix: false,
    );
  }

  String _trackingWindowLabel() =>
      '${_trackingStartHour.toString().padLeft(2, '0')}:00 - ${_trackingEndHour.toString().padLeft(2, '0')}:00';

  void _setConnectionMessage(String? message) {
    _stateController.setConnectionMessage(message);
  }

  void _handleOutsideTrackingHours() {
    if (_trackingController.outsideScheduleHandled) return;
    _trackingController.resetScheduleHandled();
    final message =
        'Tracking desactivado fuera de horario (${_trackingWindowLabel()}). Puedes continuar usando la app.';
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 16:09 UTC-5 (Lima)][desc: Fuera de horario solo se detiene tracking; no se cierra sesión ni app][obj: MapScreen._handleOutsideTrackingHours]
    unawaited(_trackingController.stopTracking());
    if (mounted) {
      setState(() {
        _stateController.setIsLoading(false);
      });
    } else {
      _stateController.setIsLoading(false);
    }
    _stateController.setShutdownMessage(null);
    _showError(message);
  }

  Future<void> _handleMapLongPress(TapPosition tapPosition, LatLng point) {
    return _routeFlowController.handleMapLongPress(context, tapPosition, point);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Permite seleccionar puntos del planificador con tap (además de long-press)][obj: MapScreen._handleMapTap]
  Future<void> _handleMapTap(TapPosition tapPosition, LatLng point) {
    return _routeFlowController.handleMapTap(context, tapPosition, point);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Inicia navegación nativa Mapbox (Android) usando waypoints del planificador][obj: MapScreen._startNativeNavigation]
  Future<void> _startNativeNavigation() async {
    try {
      final stops = _routeController.plannerStops;
      final useCurrent = _routeController.useCurrentAsOrigin;
      final points = <LatLng>[
        if (useCurrent) _stateController.center,
        ...stops.map((d) => LatLng(d.latitude, d.longitude)),
      ];
      if (points.length < 2) {
        _showError('Agrega al menos origen y destino para navegar');
        return;
      }
      await NativeNavigationService.startNavigationAndroid(
        waypoints: points
            .map((p) => <String, double>{'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        mode: _routeController.routingMode,
      );
    } catch (e) {
      _showError('No se pudo iniciar navegación: $e');
    }
  }

  Future<void> _selectAndLoadHistory() async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 15:32 UTC-5 (Lima)][desc: Usa método unificado de historial (día/rango) desde el menú][obj: MapScreen._selectAndLoadHistory]
    await _historyFlowController?.selectAndLoadHistory(context);
  }

  void _showError(String message) {
    logError('Mostrando error al usuario', error: message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _stateController.setMapReady(false, notify: false);
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleManager.detach();
    _screenStateSub?.cancel();
    _locationFlowController.dispose();
    _syncStatus.removeListener(_onSyncStatusChanged);
    _timerManager.dispose();

    if (_locationService.isTracking) {
      unawaited(_locationService.stop());
    }
    
    super.dispose();
  }

  void _startBackgroundFlushTimer() {
    _timerManager.startBackgroundFlush(() async {
      final uid = _firebaseUid ?? GetIt.I<IdentityService>().uid;
      if (uid == null) return;
      await _trackingController.tryFlushPending(firebaseUid: uid);
    });
  }

  void _stopBackgroundFlushTimer() {
    _timerManager.stopBackgroundFlush();
  }

  void _startTokenRefreshTimer() {
    _timerManager.startTokenRefresh(() async {
      try {
        final token = await GetIt.I<AuthService>().ensureValidToken();
        await _apiService.updateAuthToken(token);
      } catch (e) {
        logWarn('Error refrescando token', details: e.toString());
      }
    });
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => MapSettingsSheet(
        visitController: _visitController,
        trackingController: _trackingController,
      ),
    );
    setState(() {});
  }

  Future<void> _openLayersSelector() async {
    final selected = await showDialog<BaseLayer>(
      context: context,
      builder: (ctx) => MapLayersDialog(currentLayer: _stateController.baseLayer),
    );
    if (selected != null && mounted) {
      _stateController.setBaseLayer(selected);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('base_layer', selected.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MapViewModel>(
      builder: (context, viewModel, _) {
        return Scaffold(
          appBar: _buildAppBar(),
          body: Stack(
            children: [
              _buildMapBase(),
              MapOverlayLayer(
                stateController: _stateController,
                visitController: _visitController,
                trackingController: _trackingController,
                routeController: _routeController,
                visitFlowController: _visitFlowController,
                viewModel: viewModel,
                pendingSyncIds: _syncStateController.pendingSyncIds,
                pendingQuestionnaireCounts:
                    _syncStateController.pendingQuestionnaireCounts,
                syncStatus: _syncStatus,
                trackingWindowLabel: _trackingWindowLabel(),
                pendingLocalCount: _locationFlowController.pendingLocalCount,
                lastBgFlushAt: _syncStateController.lastBgFlushAt,
                lastBgFlushStatus: _syncStateController.lastBgFlushStatus,
                onZoomIn: _zoomIn,
                onZoomOut: _zoomOut,
                onOpenLayers: _openLayersSelector,
                onOpenVisitPlan: _openVisitPlan,
                onBootstrap: _bootstrap,
                onCenterOnUser: () => _moveCameraTo(_stateController.center),
                onToggleTracking: () {
                  if (_isTracking) {
                    unawaited(_stopTracking());
                  } else {
                    unawaited(_startTracking());
                  }
                },
                onStartVerification: _startVerificationForCurrent,
                onAdvanceToNextVisit: () => unawaited(_advanceToNextVisit()),
                onPromptArrivalConfirmation: _promptArrivalConfirmation,
                onRetryConnectionPanel: _stateController.connectionMessage != null
                    ? () {
                        _stateController.setIsLoading(true);
                        _visitController.selectNextVisit(_stateController.center);
                        _setConnectionMessage(null);
                        _bootstrap();
                      }
                    : null,
                onNavigate: FeatureFlags.enableNativeNavigation
                    ? _startNativeNavigation
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return MapAppBar(
      userName: GetIt.I<IdentityService>().nombre?.trim() ?? 'Usuario',
      onRefreshLocation: _bootstrap,
      onOpenSettings: _openSettings,
      onOpenVisitPlan: _openVisitPlan,
      onSelectAndLoadHistory: _selectAndLoadHistory,
      onAttemptLogout: _attemptLogout,
    );
  }

  Widget _buildMapBase() {
    return MapWrapper(
      mapController: _mapController,
      center: _stateController.center,
      markers: MapRenderUtils.buildMarkers(
        center: _stateController.center,
        showLocationMarker: _showLocationMarker,
        target: _visitController.currentTarget,
        plannerStops: _routeController.plannerStops,
      ),
      historySegments: _stateController.showingHistory
          ? MapRenderUtils.buildHistorySegments(_stateController.historyPoints)
          : const [],
      routePoints: _stateController.showingHistory
          ? _stateController.historyPoints
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList()
          : _stateController.route,
      pendingRoutePoints: _stateController.showingHistory
          ? const []
          : _stateController.pendingRoute,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Dibuja ruta planificada en paralelo al tracking/historial][obj: MapScreen plannedRoutePoints]
      plannedRoutePoints: _routeController.activeRoute?.coordinates ?? const <LatLng>[],
      baseLayer: _stateController.baseLayer,
      onMapReady: () {
        _stateController.setMapReady(true);
        _moveCameraTo(_stateController.center);
      },
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:30 UTC-5 (Lima)][desc: Captura instancia MapboxMap para cámara/zoom cuando se usa mapa nativo][obj: MapScreen MapWrapper.onNativeMapCreated]
      onNativeMapCreated: (map) => _nativeMap = map,
      onLongPress: _handleMapLongPress,
      onTap: _handleMapTap,
    );
  }
}
