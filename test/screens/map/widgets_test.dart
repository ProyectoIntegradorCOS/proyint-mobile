import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/assigned_visit.dart';
import 'package:flutter_application_1/models/location_point.dart'; // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:33 UTC (Lima)][desc: Agrega modelo usado en pruebas de historial][obj: widgets_test.dart]
import 'package:flutter_application_1/screens/map/widgets/history_list.dart';
import 'package:flutter_application_1/screens/map/widgets/status_banner.dart';
import 'package:flutter_application_1/screens/map/widgets/visit_panel.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:33 UTC (Lima)][desc: Añade pruebas de render y callbacks para widgets de mapa][obj: widgets_test.dart]
void main() {
  testWidgets('StatusBanner muestra mensaje y ejecuta retry',
      (WidgetTester tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusBanner(
            status: TrackingStatus.offline,
            message: 'Sin conexión',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text('Sin conexión'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets('HistoryList usa itemBuilder y loadMore', (tester) async {
    final points = [
      LocationPoint(
        latitude: 1,
        longitude: 2,
        timestamp: DateTime.now(),
      ),
      LocationPoint(
        latitude: 3,
        longitude: 4,
        timestamp: DateTime.now(),
      ),
    ];
    var loadMoreCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: HistoryList(
              items: points,
              isLoading: false,
              onLoadMore: () => loadMoreCalled = true,
              itemBuilder: (context, point, index) => ListTile(
                title: Text('Punto #$index'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Punto #0'), findsOneWidget);
    await tester.fling(
      find.byType(ListView),
      const Offset(0, -300),
      1000,
    );
    await tester.pump();
    expect(loadMoreCalled, isTrue);
  });

  testWidgets('VisitPanel muestra acciones con visita activa', (tester) async {
    final visit = AssignedVisit(
      id: '1',
      name: 'Visita demo',
      latitude: 0,
      longitude: 0,
      address: 'Av. Demo 123',
    );
    var checkIn = false;
    var checkOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisitPanel(
            visit: visit,
            onCheckIn: () => checkIn = true,
            onCheckOut: () => checkOut = true,
          ),
        ),
      ),
    );

    expect(find.text('Visita demo'), findsOneWidget);
    await tester.tap(find.text('Check-in'));
    await tester.tap(find.text('Check-out'));
    expect(checkIn, isTrue);
    expect(checkOut, isTrue);
  });
}
