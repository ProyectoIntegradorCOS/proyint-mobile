import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/destination.dart';
import '../../../models/location_point.dart';
import '../widgets/map_wrapper.dart';
import '../widgets/map_marker_spec.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 18:12 UTC-5 (Lima)][desc: Extrae helpers puros de render para historial y marcadores del mapa][obj: MapRenderUtils]
abstract class MapRenderUtils {
  static List<HistoryPolylineSegment> buildHistorySegments(
    List<LocationPoint> points,
  ) {
    if (points.length < 2) return const [];

    final colors = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.teal,
      Colors.brown,
      Colors.pink,
    ];

    final segments = <HistoryPolylineSegment>[];
    String? currentKey;
    List<LatLng> currentPoints = <LatLng>[];
    Color currentColor = colors.first;
    var colorIndex = 0;

    for (final point in points) {
      final local = point.timestamp.toLocal();
      final key =
          '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      if (currentKey == null || key != currentKey) {
        if (currentPoints.length > 1) {
          segments.add(
            HistoryPolylineSegment(points: currentPoints, color: currentColor),
          );
        }
        currentPoints = <LatLng>[];
        currentKey = key;
        currentColor = colors[colorIndex % colors.length];
        colorIndex++;
      }
      currentPoints.add(LatLng(point.latitude, point.longitude));
    }

    if (currentPoints.length > 1) {
      segments.add(
        HistoryPolylineSegment(points: currentPoints, color: currentColor),
      );
    }

    return segments;
  }

  static List<MapMarkerSpec> buildMarkers({
    required LatLng center,
    required bool showLocationMarker,
    required LatLng? target,
    required List<Destination> plannerStops,
  }) {
    final markers = <MapMarkerSpec>[];

    if (showLocationMarker) {
      markers.add(
        MapMarkerSpec(
          point: center,
          kind: MapMarkerKind.userLocation,
        ),
      );
    }

    if (target != null) {
      markers.add(
        MapMarkerSpec(
          point: target,
          kind: MapMarkerKind.destination,
        ),
      );
    }

    if (plannerStops.isNotEmpty) {
      for (var i = 0; i < plannerStops.length; i++) {
        final destination = plannerStops[i];
        markers.add(
          MapMarkerSpec(
            point: LatLng(destination.latitude, destination.longitude),
            kind: MapMarkerKind.plannerStop,
            label: '${i + 1}',
          ),
        );
      }
    }

    return markers;
  }
}
