import 'package:latlong2/latlong.dart';

class RouteStepInfo {
  RouteStepInfo({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
}

class RouteLegInfo {
  RouteLegInfo({
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final double distanceMeters;
  final double durationSeconds;
}

class RouteResult {
  RouteResult({
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
    required this.legs,
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Expone orden optimizado de waypoints cuando proviene de optimized-trips][obj: RouteResult.waypointOrder]
    this.waypointOrder,
  });

  final List<LatLng> coordinates;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStepInfo> steps;
  final List<RouteLegInfo> legs;
  final List<int>? waypointOrder;
}
