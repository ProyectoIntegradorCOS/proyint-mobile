// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:15 UTC-5 (Lima)][desc: Corrige imports de modelos y widgets][obj: MapScreenController imports]
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

import '../../../models/location_point.dart';
import '../../../models/assigned_visit.dart';
import '../widgets/status_banner.dart';
import '../widgets/dialogs/map_layers_dialog.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:33 UTC (Lima)][desc: Crea controlador de estado para MapScreen][obj: MapScreenController]
class MapScreenController extends ChangeNotifier {
  bool _isTracking = false;
  bool _waitingInitialFix = false;
  String? _connectionMessage;
  String? _shutdownMessage;
  double? _lastKnownAccuracy;
  double? _lastKnownSpeed;
  DateTime? _lastFixAt;
  List<AssignedVisit> _todayVisits = const [];
  int _currentVisitIndex = -1;
  final Set<String> _completedVisitIds = <String>{};

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:35 UTC-5 (Lima)][desc: Agrega estado de carga y UI][obj: MapScreenController._isLoading/_mapReady/_backendReady/_showingHistory]
  bool _isLoading = true;
  bool _mapReady = false;
  bool _backendReady = false;
  bool _showingHistory = false;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:45 UTC-5 (Lima)][desc: Agrega estado de paginación de historial][obj: MapScreenController history pagination]
  bool _isLoadingMoreHistory = false;
  bool _hasMoreHistory = true;
  List<LocationPoint> _historyPoints = [];
  double _totalDistanceKm = 0.0;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Guarda el último rango consultado para mostrarlo en overlay de historial][obj: MapScreenController lastHistoryRange]
  DateTimeRange? _lastHistoryRange;

  bool get isTracking => _isTracking;
  bool get waitingInitialFix => _waitingInitialFix;
  String? get connectionMessage => _connectionMessage;
  String? get shutdownMessage => _shutdownMessage;
  double? get lastKnownAccuracy => _lastKnownAccuracy;
  double? get lastKnownSpeed => _lastKnownSpeed;
  DateTime? get lastFixAt => _lastFixAt;
  List<AssignedVisit> get todayVisits => _todayVisits;
  int get currentVisitIndex => _currentVisitIndex;
  Set<String> get completedVisitIds => _completedVisitIds;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:36 UTC-5 (Lima)][desc: Expone getters para estado de UI][obj: MapScreenController.isLoading/mapReady/backendReady/showingHistory]
  bool get isLoading => _isLoading;
  bool get mapReady => _mapReady;
  bool get backendReady => _backendReady;
  bool get showingHistory => _showingHistory;
  bool get isLoadingMoreHistory => _isLoadingMoreHistory;
  bool get hasMoreHistory => _hasMoreHistory;
  List<LocationPoint> get historyPoints => _historyPoints;
  double get totalDistanceKm => _totalDistanceKm;
  DateTimeRange? get lastHistoryRange => _lastHistoryRange;

  TrackingStatus get trackingStatus {
    if (_shutdownMessage != null) return TrackingStatus.error;
    if (_connectionMessage != null) return TrackingStatus.offline;
    if (_isTracking && _waitingInitialFix) return TrackingStatus.syncing;
    if (_isTracking) return TrackingStatus.active;
    return TrackingStatus.idle;
  }

  void setTrackingState({
    required bool isTracking,
    required bool waitingInitialFix,
  }) {
    _isTracking = isTracking;
    _waitingInitialFix = waitingInitialFix;
    notifyListeners();
  }

  void setConnectionMessage(String? message) {
    _connectionMessage = message;
    notifyListeners();
  }

  void setShutdownMessage(String? message) {
    _shutdownMessage = message;
    notifyListeners();
  }

  void clearMessages() {
    _connectionMessage = null;
    _shutdownMessage = null;
    notifyListeners();
  }

  void resetVisits() {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:59 UTC (Lima)][desc: Limpia visitas e índices en controlador][obj: MapScreenController.resetVisits]
    _todayVisits = const [];
    _currentVisitIndex = -1;
    _completedVisitIds.clear();
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Limpia todo el estado de sesión al cerrar sesión para que el siguiente usuario no vea datos del anterior][obj: MapScreenController.resetForNewSession]
  void resetForNewSession() {
    _route = const <LatLng>[];
    _pendingRoute = const <LatLng>[];
    _lastFixAt = null;
    _lastKnownAccuracy = null;
    _lastKnownSpeed = null;
    _todayVisits = const [];
    _currentVisitIndex = -1;
    _completedVisitIds.clear();
    notifyListeners();
  }

  void updateLastFix(LocationPoint point) {
    _lastKnownAccuracy = point.accuracy;
    _lastKnownSpeed = point.speed;
    _lastFixAt = point.timestamp;
    notifyListeners();
  }

  void setVisits(List<AssignedVisit> visits, {int currentIndex = -1}) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:55 UTC (Lima)][desc: Sincroniza visitas del día y visita actual][obj: MapScreenController.setVisits]
    _todayVisits = visits;
    _currentVisitIndex = currentIndex;
    notifyListeners();
  }

  void markVisitCompleted(int index) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:55 UTC (Lima)][desc: Marca visita como completada][obj: MapScreenController.markVisitCompleted]
    if (index >= 0 && index < _todayVisits.length) {
      _completedVisitIds.add(_todayVisits[index].id);
      notifyListeners();
    }
  }

  void markVisitCompletedById(String id) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:59 UTC (Lima)][desc: Marca visita como completada por id][obj: MapScreenController.markVisitCompletedById]
    _completedVisitIds.add(id);
    notifyListeners();
  }

  void setCurrentVisitIndex(int index) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:55 UTC (Lima)][desc: Actualiza índice de visita actual][obj: MapScreenController.setCurrentVisitIndex]
    if (index >= 0 && index < _todayVisits.length) {
      _currentVisitIndex = index;
      notifyListeners();
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 22:37 UTC-5 (Lima)][desc: Agrega setters para estado de UI][obj: MapScreenController.setIsLoading/setMapReady/setBackendReady/setShowingHistory]
  void setIsLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setMapReady(bool value, {bool notify = true}) {
    _mapReady = value;
    if (notify) {
      notifyListeners();
    }
  }

  void setBackendReady(bool value) {
    _backendReady = value;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:45 UTC-5 (Lima)][desc: Corrige setShowingHistory sin _historyPage][obj: MapScreenController.setShowingHistory]
  void setShowingHistory(bool value) {
    _showingHistory = value;
    if (!value) {
      _historyPoints = [];
      _hasMoreHistory = true;
      _isLoadingMoreHistory = false;
    }
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:45 UTC-5 (Lima)][desc: Métodos para paginación de historial][obj: MapScreenController pagination methods]
  void setHistoryPoints(List<LocationPoint> points, {bool append = false}) {
    if (append) {
      _historyPoints.addAll(points);
    } else {
      _historyPoints = points;
    }
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Setea el rango de historial seleccionado para UI][obj: MapScreenController.setLastHistoryRange]
  void setLastHistoryRange(DateTimeRange? range) {
    _lastHistoryRange = range;
    notifyListeners();
  }

  void setTotalDistance(double value) {
    _totalDistanceKm = value;
    notifyListeners();
  }

  void setLoadingMoreHistory(bool value) {
    _isLoadingMoreHistory = value;
    notifyListeners();
  }

  void setHasMoreHistory(bool value) {
    _hasMoreHistory = value;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 09:10 UTC-5 (Lima)][desc: Agrega estado de ruta para eliminar setState en MapScreen][obj: MapScreenController.route]
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:15 UTC-5 (Lima)][desc: Evita mutación in-place para que MapWrapper (Mapbox nativo) detecte cambios y redibuje polilínea][obj: MapScreenController._route]
  List<LatLng> _route = const <LatLng>[];
  List<LatLng> get route => _route;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:30 UTC-5 (Lima)][desc: Ruta pendiente (local DB) para distinguir puntos aún no enviados][obj: MapScreenController.pendingRoute]
  List<LatLng> _pendingRoute = const <LatLng>[];
  List<LatLng> get pendingRoute => _pendingRoute;

  void addRoutePoint(LatLng point) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:15 UTC-5 (Lima)][desc: Actualiza la lista por copia (nueva referencia) para disparar diffs en widgets dependientes][obj: MapScreenController.addRoutePoint]
    _route = List<LatLng>.of(_route)..add(point);
    notifyListeners();
  }

  void clearRoute() {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:15 UTC-5 (Lima)][desc: Limpia ruta reemplazando la lista para evitar referencias compartidas][obj: MapScreenController.clearRoute]
    _route = const <LatLng>[];
    notifyListeners();
  }

  void setPendingRoute(List<LatLng> points) {
    _pendingRoute = List<LatLng>.of(points);
    notifyListeners();
  }

  void clearPendingRoute() {
    _pendingRoute = const <LatLng>[];
    notifyListeners();
  }

  void resetHistory() {
    _historyPoints = [];
    _hasMoreHistory = true;
    _isLoadingMoreHistory = false;
    _totalDistanceKm = 0.0;
    _lastHistoryRange = null;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 09:20 UTC-5 (Lima)][desc: Agrega estado de centro y capa base][obj: MapScreenController.center/baseLayer]
  LatLng _center = const LatLng(-12.0464, -77.0428);
  LatLng get center => _center;
  
  BaseLayer _baseLayer = BaseLayer.streets;
  BaseLayer get baseLayer => _baseLayer;

  void setCenter(LatLng value) {
    _center = value;
    notifyListeners();
  }

  void setBaseLayer(BaseLayer value) {
    _baseLayer = value;
    notifyListeners();
  }
}
