import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_application_1/screens/map/widgets/map_view.dart';

void main() {
  group('MapView Widget Tests', () {
    final mapController = MapController();
    const center = LatLng(0, 0);

    testWidgets('renders FlutterMap with TileLayer', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MapView(
                mapController: mapController,
                center: center,
                routePoints: const [],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(TileLayer), findsOneWidget);
    });

    testWidgets('renders PolylineLayer and MarkerLayer when routePoints provided', (WidgetTester tester) async {
      final routePoints = [
        const LatLng(0, 0),
        const LatLng(1, 1),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MapView(
                mapController: mapController,
                center: center,
                routePoints: routePoints,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(find.byType(MarkerLayer), findsOneWidget);
    });

    testWidgets('renders active route polyline when activeRoutePoints provided', (WidgetTester tester) async {
      final activeRoutePoints = [
        const LatLng(0, 0),
        const LatLng(0, 1),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MapView(
                mapController: mapController,
                center: center,
                routePoints: const [],
                activeRoutePoints: activeRoutePoints,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PolylineLayer), findsOneWidget);
    });

    testWidgets('renders history markers when showingHistory is true', (WidgetTester tester) async {
      final routePoints = [
        const LatLng(0, 0),
        const LatLng(1, 1),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MapView(
                mapController: mapController,
                center: center,
                routePoints: routePoints,
                showingHistory: true,
              ),
            ),
          ),
        ),
      );

      // Should have 2 MarkerLayers: one for start/end of route, one for history flags
      expect(find.byType(MarkerLayer), findsNWidgets(2));
    });
  });
}
