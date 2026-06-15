import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // For TapPosition
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/assigned_visit.dart';
import '../../../models/destination.dart';
import '../../../services/audit_service.dart';
import '../../../services/mapbox_service.dart';
import '../../../utils/logger.dart';
import '../widgets/sheets/route_alternatives_sheet.dart';
import '../widgets/sheets/route_planner_sheet.dart';
import 'map_screen_controller.dart';
import 'route_controller.dart';
import 'visit_controller.dart';

class RouteFlowController {
  final RouteController routeController;
  final VisitController visitController;
  final MapboxService mapboxService;
  final MapScreenController stateController;
  final Function(LatLng) onArrivalMonitoring;
  final Function(LatLng) onMoveCamera;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Conserva contexto para reabrir el planificador tras seleccionar punto en mapa][obj: RouteFlowController last planner context]
  LatLng? _lastPlannerCenter;
  MapController? _lastPlannerMapController;

  RouteFlowController({
    required this.routeController,
    required this.visitController,
    required this.mapboxService,
    required this.stateController,
    required this.onArrivalMonitoring,
    required this.onMoveCamera,
  });

  Future<void> proposeInitialAlternatives(BuildContext context, List<AssignedVisit> visits, LatLng currentCenter) async {
    if (visits.isEmpty) return;
    final first = visits.first;
    
    visitController.setCurrentTarget(
      LatLng(first.latitude, first.longitude),
    );
    visitController.resetArrivalState(
      target: LatLng(first.latitude, first.longitude),
    );
    routeController.finishRoute();
    
    // Evaluate arrival immediately
    onArrivalMonitoring(currentCenter);

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => RouteAlternativesSheet(
        origin: currentCenter,
        destination: LatLng(first.latitude, first.longitude),
        mapboxService: mapboxService,
        routeController: routeController,
        routingMode: routeController.routingMode,
        onOpenExternal: (dest) => openExternalTo(context, dest),
        onRouteSelected: (route) {
          routeController.setActiveRoute(route);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Se muestra una ruta sugerida. Puedes navegar libremente.',
              ),
            ),
          );
        },
        onCustomRoute: () {
          routeController.setActiveRoute(null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Usa tu propia ruta. El sistema no registra la elección.',
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> proposeAlternativesToLatLng(BuildContext context, LatLng destination, LatLng currentCenter) async {
    visitController.setCurrentTarget(destination);
    visitController.resetArrivalState(target: destination);
    routeController.finishRoute();
    
    onArrivalMonitoring(currentCenter);

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => RouteAlternativesSheet(
        origin: currentCenter,
        destination: destination,
        mapboxService: mapboxService,
        routeController: routeController,
        routingMode: routeController.routingMode,
        onOpenExternal: (dest) => openExternalTo(context, dest),
        onRouteSelected: (route) {
          routeController.setActiveRoute(route);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Se muestra una ruta sugerida. Puedes navegar libremente.',
              ),
            ),
          );
        },
        onCustomRoute: () {
          routeController.setActiveRoute(null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Usa tu propia ruta. El sistema no registra la elección.',
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> openExternalTo(BuildContext context, LatLng destination) async {
    final mode = routeController.routingMode == RoutingMode.walking ? 'walking' : 'driving';
    final originParam = 'origin=Current+Location';
    final destinationParam =
        'destination=${destination.latitude},${destination.longitude}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&$originParam&$destinationParam&travelmode=$mode',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir Google Maps')),
      );
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Retorna Future para reutilizar lógica desde tap/long-press][obj: RouteFlowController.handleMapLongPress]
  Future<void> handleMapLongPress(BuildContext context, TapPosition tapPosition, LatLng point) async {
    if (!(routeController.plannerActive || routeController.selectingOnMap)) return;
    
    String name;
    try {
      name = await mapboxService.reverseGeocode(point);
    } catch (_) {
      name = '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    }
    
    if (routeController.plannerStops.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo 5 destinos')),
      );
      return;
    }

    routeController.addStop(
      Destination(
        id: 'map_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        latitude: point.latitude,
        longitude: point.longitude,
        source: DestinationSource.map,
      ),
    );
    
    if (routeController.selectingOnMap) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Al seleccionar en mapa, reabre automáticamente el planificador y desactiva modo selección][obj: RouteFlowController handleMapLongPress reopen]
      routeController.setSelectingOnMap(false);
      if (_lastPlannerCenter != null && _lastPlannerMapController != null) {
        unawaited(openRoutePlanner(context, _lastPlannerCenter!, _lastPlannerMapController!));
      } else {
        logWarn('No hay contexto para reabrir planificador tras selección en mapa');
      }
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Permite agregar destino con tap (misma lógica que long-press)][obj: RouteFlowController.handleMapTap]
  Future<void> handleMapTap(BuildContext context, TapPosition tapPosition, LatLng point) async {
    await handleMapLongPress(context, tapPosition, point);
  }

  Future<void> openRoutePlanner(BuildContext context, LatLng center, MapController mapController) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Guarda contexto de planificador para reabrirlo tras seleccionar en mapa][obj: RouteFlowController.openRoutePlanner store context]
    _lastPlannerCenter = center;
    _lastPlannerMapController = mapController;
    routeController.setPlannerActive(true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => RoutePlannerSheet(
        routeController: routeController,
        mapboxService: mapboxService,
        center: center,
        mapController: mapController,
        onError: (msg) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        },
      ),
    );
    routeController.setPlannerActive(false);
  }

  void markRouteStarted(BuildContext context, LatLng center) {
    if (routeController.routeInProgress) return;
    routeController.markRouteStarted();
    unawaited(
      AuditService.instance.logEvent('route_started', {
        'lat': center.latitude,
        'lng': center.longitude,
        'visitIndex': stateController.currentVisitIndex,
      }),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recorrido iniciado')),
    );
  }
}
