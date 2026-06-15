import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../../models/destination.dart';
import '../../../../models/route_models.dart';
import '../../../../services/mapbox_service.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:15 UTC-5 (Lima)][desc: Crea controlador especializado para planificación de rutas][obj: RouteController]
class RouteController extends ChangeNotifier {
  final MapboxService _mapboxService;

  RouteController({required MapboxService mapboxService})
      : _mapboxService = mapboxService;

  final List<Destination> _plannerStops = [];
  RoutingMode _routingMode = RoutingMode.walking;
  bool _optimizeStops = true;
  RouteResult? _activeRoute;
  bool _plannerActive = false;
  bool _fixOriginFirst = true;
  bool _fixDestinationLast = true;
  bool _useCurrentAsOrigin = true;
  bool _selectingOnMap = false;
  bool _routeInProgress = false;
  bool _startNotified = false;

  List<Destination> get plannerStops => _plannerStops;
  RoutingMode get routingMode => _routingMode;
  bool get optimizeStops => _optimizeStops;
  RouteResult? get activeRoute => _activeRoute;
  bool get plannerActive => _plannerActive;
  bool get fixOriginFirst => _fixOriginFirst;
  bool get fixDestinationLast => _fixDestinationLast;
  bool get useCurrentAsOrigin => _useCurrentAsOrigin;
  bool get selectingOnMap => _selectingOnMap;
  bool get routeInProgress => _routeInProgress;
  bool get startNotified => _startNotified;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:17 UTC-5 (Lima)][desc: Agrega parada al planificador][obj: RouteController.addStop]
  void addStop(Destination destination) {
    _plannerStops.add(destination);
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:17 UTC-5 (Lima)][desc: Elimina parada del planificador][obj: RouteController.removeStop]
  void removeStop(int index) {
    if (index >= 0 && index < _plannerStops.length) {
      _plannerStops.removeAt(index);
      notifyListeners();
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:18 UTC-5 (Lima)][desc: Limpia todas las paradas][obj: RouteController.clearStops]
  void clearStops() {
    _plannerStops.clear();
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Reemplaza lista de paradas (para aplicar orden optimizado)][obj: RouteController.replaceStops]
  void replaceStops(List<Destination> stops) {
    _plannerStops
      ..clear()
      ..addAll(stops);
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:18 UTC-5 (Lima)][desc: Establece modo de ruta][obj: RouteController.setRoutingMode]
  void setRoutingMode(RoutingMode mode) {
    _routingMode = mode;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:18 UTC-5 (Lima)][desc: Activa/desactiva optimización de paradas][obj: RouteController.setOptimizeStops]
  void setOptimizeStops(bool value) {
    _optimizeStops = value;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:19 UTC-5 (Lima)][desc: Establece ruta activa][obj: RouteController.setActiveRoute]
  void setActiveRoute(RouteResult? route) {
    _activeRoute = route;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:19 UTC-5 (Lima)][desc: Activa/desactiva planificador][obj: RouteController.setPlannerActive]
  void setPlannerActive(bool value) {
    _plannerActive = value;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:19 UTC-5 (Lima)][desc: Configura opciones de origen/destino][obj: RouteController.configureOriginDestination]
  void configureOriginDestination({
    bool? fixOrigin,
    bool? fixDestination,
    bool? useCurrentAsOrigin,
  }) {
    if (fixOrigin != null) _fixOriginFirst = fixOrigin;
    if (fixDestination != null) _fixDestinationLast = fixDestination;
    if (useCurrentAsOrigin != null) _useCurrentAsOrigin = useCurrentAsOrigin;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:20 UTC-5 (Lima)][desc: Establece modo de selección en mapa][obj: RouteController.setSelectingOnMap]
  void setSelectingOnMap(bool value) {
    _selectingOnMap = value;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:20 UTC-5 (Lima)][desc: Marca inicio de recorrido][obj: RouteController.markRouteStarted]
  void markRouteStarted() {
    _routeInProgress = true;
    _startNotified = true;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:20 UTC-5 (Lima)][desc: Finaliza recorrido][obj: RouteController.finishRoute]
  void finishRoute() {
    _routeInProgress = false;
    _activeRoute = null;
    _startNotified = false;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:25 UTC-5 (Lima)][desc: Calcula ruta con Mapbox usando waypoints][obj: RouteController.calculateRoute]
  Future<RouteResult?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? additionalWaypoints,
  }) async {
    try {
      // Construye lista de waypoints: origen + intermedios + destino
      final allWaypoints = [
        origin,
        if (additionalWaypoints != null) ...additionalWaypoints,
        destination,
      ];

      final result = await _mapboxService.directions(
        mode: _routingMode,
        waypoints: allWaypoints,
      );

      _activeRoute = result;
      notifyListeners();

      return result;
    } catch (e) {
      debugPrint('Error calculando ruta: $e');
      return null;
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:22 UTC-5 (Lima)][desc: Obtiene alternativas de ruta][obj: RouteController.getAlternativeRoutes]
  Future<List<RouteResult>> getAlternativeRoutes({
    required LatLng origin,
    required LatLng destination,
    int maxAlternatives = 3,
  }) async {
    try {
      // Por ahora retorna lista vacía, se puede implementar llamada a API de alternativas
      return [];
    } catch (e) {
      debugPrint('Error obteniendo alternativas: $e');
      return [];
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:22 UTC-5 (Lima)][desc: Resetea estado del controlador][obj: RouteController.reset]
  void reset() {
    _plannerStops.clear();
    _activeRoute = null;
    _plannerActive = false;
    _selectingOnMap = false;
    _routeInProgress = false;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:23 UTC-5 (Lima)][desc: Reordena paradas][obj: RouteController.reorderStops]
  void reorderStops(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _plannerStops.removeAt(oldIndex);
    _plannerStops.insert(newIndex, item);
    notifyListeners();
  }
}
