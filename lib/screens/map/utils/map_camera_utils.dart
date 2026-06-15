import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../../../config/feature_flags.dart';
import '../../../utils/logger.dart';

/// Utilidades de cámara y zoom para el mapa.
/// Métodos estáticos puros (sin estado), fáciles de testear aisladamente.
abstract class MapCameraUtils {
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:30 UTC-5 (Lima)][desc: Mueve cámara usando MapboxMap cuando está activo el mapa nativo][obj: MapCameraUtils.moveCameraTo native]
  static void moveCameraTo({
    required MapController mapController,
    required mb.MapboxMap? nativeMap,
    required bool mapReady,
    required LatLng target,
  }) {
    if (!mapReady) return;
    if (FeatureFlags.enableNativeMapboxMap) {
      final map = nativeMap;
      if (map == null) return;
      () async {
        try {
          final cs = await map.getCameraState();
          await map.setCamera(
            mb.CameraOptions(
              center: mb.Point(
                  coordinates: mb.Position(target.longitude, target.latitude)),
              zoom: cs.zoom,
            ),
          );
        } catch (error, stackTrace) {
          logError(
            'No se pudo mover la cámara del mapa (native)',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }();
      return;
    }
    try {
      final zoom = mapController.camera.zoom;
      mapController.move(target, zoom);
    } catch (error, stackTrace) {
      logError(
        'No se pudo mover la cámara del mapa',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:30 UTC-5 (Lima)][desc: Zoom +/- usando MapboxMap cuando está activo el mapa nativo][obj: MapCameraUtils.zoomBy native]
  static void zoomBy({
    required MapController mapController,
    required mb.MapboxMap? nativeMap,
    required bool mapReady,
    required double delta,
  }) {
    if (!mapReady) return;
    if (FeatureFlags.enableNativeMapboxMap) {
      final map = nativeMap;
      if (map == null) return;
      () async {
        try {
          final cs = await map.getCameraState();
          final newZoom = (cs.zoom + delta).clamp(1.0, 19.0);
          await map.setCamera(mb.CameraOptions(zoom: newZoom));
        } catch (error, stackTrace) {
          logError(
            'No se pudo ajustar el zoom (native)',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }();
      return;
    }
    try {
      final camera = mapController.camera;
      final newZoom = (camera.zoom + delta).clamp(1.0, 19.0);
      mapController.move(camera.center, newZoom);
    } catch (error, stackTrace) {
      logError(
        'No se pudo ajustar el zoom',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
