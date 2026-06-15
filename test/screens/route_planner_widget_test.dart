import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_application_1/screens/map/controllers/route_controller.dart';
import 'package:flutter_application_1/screens/map/widgets/sheets/route_planner_sheet.dart';
import 'package:flutter_application_1/services/mapbox_service.dart';

void main() {
  testWidgets('abre planificador y muestra controles basicos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutePlannerSheet(
            routeController: RouteController(
              mapboxService: MapboxService(accessToken: 'pk.test'),
            ),
            mapboxService: MapboxService(accessToken: 'pk.test'),
            center: const LatLng(-12.05, -77.05),
            mapController: MapController(),
            onError: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Planificador de ruta'), findsOneWidget);
    expect(find.text('Caminar'), findsOneWidget);
    expect(find.text('Conducir (aprox. bus)'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Añadir'), findsOneWidget);
  });
}
