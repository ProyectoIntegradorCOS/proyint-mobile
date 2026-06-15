import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/mapbox_config.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:51 UTC (Lima)][desc: Implementa MapView con flutter_map y capas reutilizables][obj: MapView]
class MapView extends StatelessWidget {
  const MapView({
    super.key,
    required this.mapController,
    required this.center,
    required this.routePoints,
    this.activeRoutePoints = const [],
    this.showingHistory = false,
    this.arrivalConfirmed = false,
    this.mapboxEnabled = false,
    this.mapboxStyleId,
    this.onMapReady,
    this.onLongPress,
    this.onTap,
  });

  final MapController mapController;
  final LatLng center;
  final List<LatLng> routePoints;
  final List<LatLng> activeRoutePoints;
  final bool showingHistory;
  final bool arrivalConfirmed;
  final bool mapboxEnabled;
  final String? mapboxStyleId;
  final VoidCallback? onMapReady;
  final void Function(TapPosition, LatLng)? onLongPress;
  final void Function(TapPosition, LatLng)? onTap;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
        onMapReady: onMapReady,
        onLongPress: onLongPress,
        onTap: onTap,
      ),
      children: [
        TileLayer(
          urlTemplate: mapboxEnabled
              ? 'https://api.mapbox.com/styles/v1/{styleId}/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          additionalOptions: mapboxEnabled
              ? {
                  'accessToken': MapboxConfig.accessToken,
                  'styleId': mapboxStyleId ?? MapboxConfig.styleId,
                }
              : const <String, String>{},
          userAgentPackageName: 'com.example.flutter_application_1',
        ),
        if (routePoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                color: Colors.blue,
                strokeWidth: 4,
              ),
            ],
          ),
        if (routePoints.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: routePoints.first,
                width: 36,
                height: 36,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.green,
                  size: 36,
                ),
              ),
              Marker(
                point: routePoints.last,
                width: 36,
                height: 36,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 36,
                ),
              ),
            ],
          ),
        if (activeRoutePoints.isNotEmpty && !arrivalConfirmed)
          PolylineLayer(
            polylines: [
              Polyline(
                points: activeRoutePoints,
                color: Colors.deepPurple,
                strokeWidth: 5,
              ),
            ],
          ),
        if (routePoints.isEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 32,
                height: 32,
                child: const Icon(
                  Icons.my_location,
                  color: Colors.blue,
                  size: 32,
                ),
              ),
            ],
          ),
        if (showingHistory && routePoints.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: routePoints.first,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.flag,
                  color: Colors.orange,
                  size: 40,
                ),
              ),
              Marker(
                point: routePoints.last,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.flag,
                  color: Colors.purple,
                  size: 40,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
