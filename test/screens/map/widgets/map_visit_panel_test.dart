import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/map/widgets/map_visit_panel.dart';
import 'package:flutter_application_1/screens/map/widgets/status_banner.dart';
import 'package:flutter_application_1/screens/map/widgets/visit_panel.dart';
import 'package:flutter_application_1/screens/map/widgets/tracking_info_chip.dart';
import 'package:flutter_application_1/models/assigned_visit.dart';

void main() {
  group('MapVisitPanel Widget Tests', () {
    final visit = AssignedVisit(
      id: '1',
      name: 'Test Visit',
      address: 'Test Address',
      latitude: 0,
      longitude: 0,
      scheduledAt: DateTime.now(),
    );

    testWidgets('renders StatusBanner, VisitPanel, and TrackingInfoChip', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapVisitPanel(
              trackingStatus: TrackingStatus.active,
              showTrackingInfo: true,
              currentVisit: visit,
              onCheckIn: () {},
              onCheckOut: () {},
              onValidate: () {},
            ),
          ),
        ),
      );

      expect(find.byType(StatusBanner), findsOneWidget);
      expect(find.byType(VisitPanel), findsOneWidget);
      expect(find.byType(TrackingInfoChip), findsOneWidget);
    });

    testWidgets('passes status to StatusBanner', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapVisitPanel(
              trackingStatus: TrackingStatus.offline,
              onCheckIn: () {},
              onCheckOut: () {},
              onValidate: () {},
            ),
          ),
        ),
      );

      expect(find.text('Sin conexión. Se guardan ubicaciones en el dispositivo.'), findsOneWidget);
    });

    testWidgets('passes visit to VisitPanel', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapVisitPanel(
              trackingStatus: TrackingStatus.active,
              currentVisit: visit,
              onCheckIn: () {},
              onCheckOut: () {},
              onValidate: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Visit'), findsOneWidget);
      expect(find.text('Test Address'), findsOneWidget);
    });

    // Note: Testing callbacks requires knowing the internal structure of VisitPanel to find the buttons.
    // Assuming VisitPanel has buttons with specific text or keys.
    // For now, we verify composition and data passing which is the main responsibility of MapVisitPanel.
  });
}
