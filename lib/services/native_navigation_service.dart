import 'dart:io';

import 'package:flutter/services.dart';

import '../config/mapbox_config.dart';
import '../services/mapbox_service.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Bridge Flutter->Android para iniciar navegación nativa Mapbox (Navigation SDK)][obj: NativeNavigationService]
class NativeNavigationService {
  static const MethodChannel _channel = MethodChannel('pe.gob.onp.thaqhiri/navigation');

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Inicia navegación nativa (Android) con waypoints y perfil][obj: NativeNavigationService.startNavigationAndroid]
  static Future<void> startNavigationAndroid({
    required List<Map<String, double>> waypoints,
    required RoutingMode mode,
  }) async {
    if (!Platform.isAndroid) return;
    if (waypoints.length < 2) {
      throw ArgumentError('Se requieren al menos 2 puntos para navegar');
    }
    final accessToken = MapboxConfig.accessToken;
    if (accessToken.isEmpty) {
      throw StateError('MAPBOX_ACCESS_TOKEN no configurado');
    }

    final profile = switch (mode) {
      RoutingMode.walking => 'walking',
      RoutingMode.drivingTraffic => 'driving-traffic',
      RoutingMode.driving => 'driving',
    };

    await _channel.invokeMethod('startNavigation', {
      'accessToken': accessToken,
      'profile': profile,
      'waypoints': waypoints,
    });
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Actualiza ruta en caliente (si NavigationActivity está abierta) enviando waypoints al canal nativo][obj: NativeNavigationService.updateRouteAndroid]
  static Future<void> updateRouteAndroid({
    required List<Map<String, double>> waypoints,
    required RoutingMode mode,
  }) async {
    if (!Platform.isAndroid) return;
    if (waypoints.length < 2) {
      throw ArgumentError('Se requieren al menos 2 puntos para actualizar ruta');
    }
    final profile = switch (mode) {
      RoutingMode.walking => 'walking',
      RoutingMode.drivingTraffic => 'driving-traffic',
      RoutingMode.driving => 'driving',
    };
    await _channel.invokeMethod('updateRoute', {
      'profile': profile,
      'waypoints': waypoints,
    });
  }
}
