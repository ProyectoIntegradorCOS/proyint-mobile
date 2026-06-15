import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/location_point.dart';
import '../../../models/visit_plan.dart';
import '../../../services/api_service.dart';
import '../../../services/location_service.dart';
import '../../../services/location_sync_manager.dart';
import '../../../services/mapbox_service.dart';
import '../../../services/pending_location_store.dart';
import '../../../utils/logger.dart';
import 'map_screen_controller.dart';
import 'tracking_controller.dart';
import 'visit_controller.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 18:12 UTC-5 (Lima)][desc: Extrae del State la orquestación de ubicación, cola local y toma de puntos en foreground/background][obj: LocationFlowController]
class LocationFlowController {
  LocationFlowController({
    required ApiService apiService,
    required LocationService locationService,
    required LocationSyncManager syncManager,
    required PendingLocationStore pendingLocationStore,
    required TrackingController trackingController,
    required MapScreenController stateController,
    required VisitController visitController,
    required String? Function() getFirebaseUid,
    required Future<void> Function() onLoadBgFlushInfo,
    required void Function(LatLng) onMoveCamera,
    required void Function() onArrivalDetected,
    required Future<void> Function(LatLng, VisitItem?) onPromptArrivalConfirmation,
    required Future<void> Function() onMovedBeyondRadius,
  })  : _apiService = apiService,
        _locationService = locationService,
        _syncManager = syncManager,
        _pendingLocationStore = pendingLocationStore,
        _trackingController = trackingController,
        _stateController = stateController,
        _visitController = visitController,
        _getFirebaseUid = getFirebaseUid,
        _onLoadBgFlushInfo = onLoadBgFlushInfo,
        _onMoveCamera = onMoveCamera,
        _onArrivalDetected = onArrivalDetected,
        _onPromptArrivalConfirmation = onPromptArrivalConfirmation,
        _onMovedBeyondRadius = onMovedBeyondRadius;

  final ApiService _apiService;
  final LocationService _locationService;
  final LocationSyncManager _syncManager;
  final PendingLocationStore _pendingLocationStore;
  final TrackingController _trackingController;
  final MapScreenController _stateController;
  final VisitController _visitController;
  final String? Function() _getFirebaseUid;
  final Future<void> Function() _onLoadBgFlushInfo;
  final void Function(LatLng) _onMoveCamera;
  final void Function() _onArrivalDetected;
  final Future<void> Function(LatLng, VisitItem?) _onPromptArrivalConfirmation;
  final Future<void> Function() _onMovedBeyondRadius;

  StreamSubscription<LocationPoint>? _locationStreamSub;

  LatLng? _pendingRouteDestination;
  RoutingMode? _pendingRouteMode;
  var _pendingDrawOptimalRoute = false;
  Future<void> Function(LatLng current, LatLng destination, RoutingMode mode)?
      _onDrawPendingRoute;

  int? _pendingLocalCount;
  int? get pendingLocalCount => _pendingLocalCount;

  void handleArrivalMonitoring(LatLng current) {
    _handleArrivalMonitoring(current);
  }

  void setPendingRouteRequest({
    required LatLng destination,
    required RoutingMode mode,
    required bool drawOptimalRoute,
  }) {
    _pendingRouteDestination = destination;
    _pendingRouteMode = mode;
    _pendingDrawOptimalRoute = drawOptimalRoute;
  }

  void setDrawPendingRouteHandler(
    Future<void> Function(LatLng current, LatLng destination, RoutingMode mode)
        handler,
  ) {
    _onDrawPendingRoute = handler;
  }

  void attachLocationStream() {
    _locationStreamSub?.cancel();
    _locationStreamSub = _locationService.stream.listen(_handleLocationPoint);
  }

  Future<void> hydrateRouteFromBackground() async {
    final uid = _getFirebaseUid();
    if (uid == null) return;
    final lastFix = _stateController.lastFixAt;
    if (lastFix == null) return;

    final now = DateTime.now();
    final gapSeconds = now.difference(lastFix).inSeconds;
    if (gapSeconds < 20) return;

    final maxLookback = const Duration(hours: 4);
    final start =
        gapSeconds > maxLookback.inSeconds ? now.subtract(maxLookback) : lastFix;

    try {
      final history = await _apiService.fetchLocationHistory(
        firebaseUid: uid,
        startDate: start,
        endDate: now,
      );
      if (history.points.isEmpty) return;

      final newPoints =
          history.points.where((p) => p.timestamp.isAfter(lastFix)).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (newPoints.isEmpty) return;

      final accepted = <LocationPoint>[];
      for (final point in newPoints) {
        final filtered = _trackingController.filterPoint(point);
        if (filtered == null) continue;
        accepted.add(filtered);
        _stateController.addRoutePoint(
          LatLng(filtered.latitude, filtered.longitude),
        );
      }
      if (accepted.isEmpty) return;

      _stateController.updateLastFix(accepted.last);
    } catch (e) {
      logWarn(
        'No se pudo hidratar ruta desde background',
        details: e.toString(),
      );
    }
  }

  Future<void> refreshPendingRouteFromLocal() async {
    final uid = _getFirebaseUid();
    if (uid == null) {
      _pendingLocalCount = null;
      return;
    }
    try {
      await _onLoadBgFlushInfo();
      final pending = await _syncManager.getPendingPointsForSubject(uid);
      if (pending.isEmpty) {
        _pendingLocalCount = 0;
        _stateController.clearPendingRoute();
        return;
      }

      _pendingLocalCount = pending.length;
      final filtered = <LatLng>[];
      for (final point in pending) {
        final accepted = _trackingController.filterPoint(point);
        if (accepted == null) continue;
        filtered.add(LatLng(accepted.latitude, accepted.longitude));
      }
      _stateController.setPendingRoute(filtered);
    } catch (e) {
      logWarn(
        'No se pudo refrescar ruta pendiente',
        details: e.toString(),
      );
    }
  }

  Future<void> refreshPendingLocalCount() async {
    final uid = _getFirebaseUid();
    if (uid == null || uid.isEmpty) {
      _pendingLocalCount = null;
      return;
    }
    try {
      _pendingLocalCount = await _pendingLocationStore.countForSubject(uid);
    } catch (_) {}
  }

  Future<void> syncLocation(LocationPoint point) async {
    final uid = _getFirebaseUid();
    if (uid == null || uid.isEmpty || !_trackingController.isTracking) return;
    try {
      final batteryLevel = await Battery().batteryLevel;
      await _trackingController.processLocationUpdate(
        firebaseUid: uid,
        point: point,
        batteryLevel: batteryLevel,
        activityType: 'unknown',
      );
      _stateController.setBackendReady(true);
      _stateController.setConnectionMessage(null);
      await refreshPendingLocalCount();
    } catch (e) {
      logError('Error sincronizando ubicación', error: e);
      _stateController.setBackendReady(false);
      _stateController.setConnectionMessage('Sin conexión con el servidor');
    }
  }

  void dispose() {
    _locationStreamSub?.cancel();
    _locationStreamSub = null;
  }

  void _handleLocationPoint(LocationPoint rawPoint) {
    final filtered = _trackingController.filterPoint(rawPoint);
    if (filtered == null) return;

    final point = LatLng(filtered.latitude, filtered.longitude);
    _stateController.addRoutePoint(point);
    _stateController.setCenter(point);
    _trackingController.setWaitingInitialFix(false);
    _stateController.setTrackingState(
      isTracking: _trackingController.isTracking,
      waitingInitialFix: false,
    );
    _stateController.updateLastFix(filtered);
    _onMoveCamera(point);
    unawaited(syncLocation(filtered));
    _handleArrivalMonitoring(point);
    _visitController.checkSmartAlerts(point);
    _tryRunPendingRoute(point);
  }

  void _handleArrivalMonitoring(LatLng current) {
    final target = _visitController.currentTarget;
    if (target == null) return;
    final distance =
        Distance().as(LengthUnit.Meter, current, target);
    final inside = distance <= _visitController.arrivalRadiusMeters;
    final activePlan = _visitController.activePlanVisit;
    final alreadyArrived = _visitController.arrivalConfirmed ||
        (activePlan != null &&
            (activePlan.state == VisitItemState.onSite ||
                activePlan.state == VisitItemState.inVisit ||
                activePlan.state == VisitItemState.done));
    final shouldPromptByState =
        activePlan != null && activePlan.state == VisitItemState.enRoute;
    if (inside &&
        !_visitController.wasInsideArrivalZone &&
        !alreadyArrived &&
        shouldPromptByState) {
      _onArrivalDetected();
      unawaited(_onPromptArrivalConfirmation(current, activePlan));
    }
    _visitController.updateArrivalZoneState(inside);

    if (_visitController.dwellInProgress) {
      final ref = _visitController.arrivalRefPoint ?? target;
      final moved = Distance().as(LengthUnit.Meter, current, ref);
      if (moved > _visitController.arrivalRadiusMeters) {
        unawaited(_onMovedBeyondRadius());
      }
    }
  }

  void _tryRunPendingRoute(LatLng current) {
    final destination = _pendingRouteDestination;
    final mode = _pendingRouteMode;
    if (destination == null || mode == null) return;
    if (_trackingController.waitingInitialFix) return;

    final shouldDraw = _pendingDrawOptimalRoute;
    _pendingRouteDestination = null;
    _pendingRouteMode = null;
    _pendingDrawOptimalRoute = false;

    if (!shouldDraw) return;

    final handler = _onDrawPendingRoute;
    if (handler == null) return;
    unawaited(handler(current, destination, mode));
  }
}
