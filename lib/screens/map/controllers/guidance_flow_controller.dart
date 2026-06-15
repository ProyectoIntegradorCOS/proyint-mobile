import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';
import '../../../models/visit_plan.dart';
import '../../../models/route_models.dart';
import '../../../services/mapbox_service.dart';
import '../../../services/api_service.dart';
import '../../../services/visit_state_sync_manager.dart';
import '../../../services/offline_visit_event_store.dart';
import '../../../services/visit_plan_cache_store.dart';
import '../widgets/dialogs/guidance_mode_sheet.dart';
import 'map_screen_controller.dart';
import 'route_controller.dart';
import 'tracking_controller.dart';
import 'visit_controller.dart';

class GuidanceFlowController {
  final VisitController visitController;
  final RouteController routeController;
  final TrackingController trackingController;
  final MapScreenController stateController;
  final ApiService apiService;

  // Callbacks to MapScreen
  final Future<void> Function(LatLng current, VisitItem? item) onPromptArrivalConfirmation;
  final Function(String) onError;
  final Function(String) onSnack;
  final Function() onOutsideSchedule;
  final bool Function() getEnforceEndHour;
  final void Function(LatLng, RoutingMode) onPendingRouteCalculated;
  final OfflineVisitEventStore _eventStore = OfflineVisitEventStore();
  final VisitPlanCacheStore _planCache = VisitPlanCacheStore();

  GuidanceFlowController({
    required this.visitController,
    required this.routeController,
    required this.trackingController,
    required this.stateController,
    required this.apiService,
    required this.onPromptArrivalConfirmation,
    required this.onError,
    required this.onSnack,
    required this.onOutsideSchedule,
    required this.getEnforceEndHour,
    required this.onPendingRouteCalculated,
  });

  Future<void> startGuidanceFromPlanVisit(
    BuildContext context, 
    VisitItem item, 
    bool isInsideArrivalZoneNow,
  ) async {
    final lat = item.latitude;
    final lng = item.longitude;
    if (lat == null ||
        lng == null ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        (lat == 0 && lng == 0)) {
      onError('El destino no tiene coordenadas (lat/lng).');
      return;
    }
    final destination = LatLng(lat, lng);

    final previousTarget = visitController.currentTarget;
    final previousPlanVisit = visitController.activePlanVisit;

    // Setear target para arrival detection y monitoreo de salida del radio.
    visitController.setCurrentTarget(destination);
    visitController.resetArrivalState(target: destination);
    visitController.setActivePlanVisit(item);
    routeController.finishRoute();

    // Asegurar tracking para que corra evaluación de llegada y se guarde el recorrido.
    final trackingOk = await ensureTrackingActiveForGuidance();
    if (!trackingOk) return;

    if (!trackingController.waitingInitialFix &&
        isInsideArrivalZoneNow &&
        item.state == VisitItemState.enRoute) {
      await onPromptArrivalConfirmation(stateController.center, visitController.activePlanVisit);
      return;
    }

    if (!context.mounted) return;
    final choice = await GuidanceModeSheet.show(context, routeController.routingMode);
    if (!context.mounted || choice == null) {
      visitController.resetArrivalState(target: previousTarget);
      visitController.setActivePlanVisit(previousPlanVisit);
      if (previousTarget == null) {
        routeController.finishRoute();
      }
      return;
    }

    routeController.setRoutingMode(choice.mode);

    final updated = await ensurePlanVisitEnRoute(item);
    if (updated == null) {
      visitController.resetArrivalState(target: previousTarget);
      visitController.setActivePlanVisit(previousPlanVisit);
      return;
    }
    visitController.setActivePlanVisit(updated);

    if (!choice.drawOptimalRoute) {
      routeController.finishRoute();
      onSnack('Guía manual: sigue tu propia ruta');
      return;
    }

    // Si todavía no hay primer fix, dejamos pendiente el cálculo para cuando llegue.
    if (trackingController.waitingInitialFix) {
      onPendingRouteCalculated(destination, choice.mode);
      onSnack('Obteniendo ubicación para calcular ruta…');
      return;
    }

    await drawOptimalRouteFrom(
      current: stateController.center,
      destination: destination,
      mode: choice.mode,
    );
  }

  Future<bool> ensureTrackingActiveForGuidance() async {
    if (trackingController.isTracking) return true;
    final ok = await trackingController.startTracking(
      onError: onError,
      onOutsideSchedule: onOutsideSchedule,
      enforceEndHour: getEnforceEndHour(),
    );
    stateController.setTrackingState(
      isTracking: trackingController.isTracking,
      waitingInitialFix: trackingController.waitingInitialFix,
    );
    if (!ok) {
      onError('Tracking desactivado. Puedes continuar usando la app (rutas y visitas).');
      return true; // No bloquear la guía si el tracking no puede iniciar.
    }
    return true;
  }

  Future<VisitItem?> ensurePlanVisitEnRoute(VisitItem item) async {
    if (item.state == VisitItemState.enRoute ||
        item.state == VisitItemState.onSite ||
        item.state == VisitItemState.inVisit) {
      return item;
    }
    try {
      final current = stateController.center;
      await _eventStore.enqueue(
        visitId: item.id,
        eventType: VisitItemState.enRoute.apiValue,
        timestamp: DateTime.now(),
        latitude: current.latitude,
        longitude: current.longitude,
      );
      final updated = item.copyWith(state: VisitItemState.enRoute);
      visitController.setActivePlanVisit(updated);
      visitController.updatePlanItemState(item.id, VisitItemState.enRoute);
      await _planCache.updateItemState(itemId: item.id, newState: VisitItemState.enRoute);
      GetIt.I<VisitStateSyncManager>().triggerNow();
      onSnack('Inicio de recorrido guardado para sincronizar.');
      return updated;
    } catch (e) {
      onError('No se pudo iniciar el recorrido: $e');
      return null;
    }
  }

  Future<void> drawOptimalRouteFrom({
    required LatLng current,
    required LatLng destination,
    required RoutingMode mode,
  }) async {
    try {
      routeController.setRoutingMode(mode);
      final route = await routeController.calculateRoute(
        origin: current,
        destination: destination,
      );
      if (route == null) {
        onError('No se pudo calcular la ruta.');
        return;
      }
      onSnack('Ruta dibujada (${_routeLabel(mode)})');
    } catch (e) {
      onError('No se pudo calcular la ruta: $e');
    }
  }

  String _routeLabel(RoutingMode mode) {
    switch (mode) {
      case RoutingMode.walking:
        return 'caminando';
      case RoutingMode.driving:
        return 'auto';
      case RoutingMode.drivingTraffic:
        return 'bus/auto (tráfico)';
    }
  }
}
