import 'package:flutter/material.dart';
import '../../models/assigned_visit.dart';
import '../../models/location_point.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';

import 'controllers/map_screen_controller.dart';
import 'controllers/visit_controller.dart';
import 'controllers/tracking_controller.dart';
import 'controllers/route_controller.dart';
import '../../services/location_service.dart';

class MapViewModel extends ChangeNotifier {
  final MapScreenController stateController;
  final VisitController visitController;
  final TrackingController trackingController;
  final RouteController routeController;
  final LocationService _locationService = GetIt.I<LocationService>();

  MapViewModel({
    required this.stateController,
    required this.visitController,
    required this.trackingController,
    required this.routeController,
  }) {
    // Escuchar cambios en los submódulos para notificar a la vista raíz
    stateController.addListener(notifyListeners);
    visitController.addListener(notifyListeners);
    routeController.addListener(notifyListeners);
  }

  // --- Derived State Computations ---
  
  List<AssignedVisit> get todayVisits => visitController.todayVisits;
  int get currentVisitIndex => visitController.currentVisitIndex;
  
  AssignedVisit? get currentVisit {
    if (currentVisitIndex >= 0 && currentVisitIndex < todayVisits.length) {
      return todayVisits[currentVisitIndex];
    }
    return null;
  }

  int get pendingVisitsCount {
    final completedUnion = <String>{
      ...visitController.completedVisitIds,
    };
    return todayVisits.where((v) {
      final completedByFlag = v.confirmed == true;
      final completedByRuntime = completedUnion.contains(v.id);
      return !(completedByFlag || completedByRuntime);
    }).length;
  }

  int get completedVisitsCount {
    return visitController.completedVisitIds.length +
        todayVisits.where((v) => v.confirmed == true).length;
  }

  int get totalVisitsCount => todayVisits.length;

  bool get hasPendingVisits => pendingVisitsCount > 0;

  // --- Map Controls ---
  
  void moveToLocation(LatLng target) {
    // La UI reaccionará si lo conectamos mediante un controller interno del mapa,
    // pero la lógica de cálculo debe residir aquí.
  }

  @override
  void dispose() {
    stateController.removeListener(notifyListeners);
    visitController.removeListener(notifyListeners);
    routeController.removeListener(notifyListeners);
    super.dispose();
  }
}
