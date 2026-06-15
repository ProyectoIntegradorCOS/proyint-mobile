import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/map/widgets/status_banner.dart';

void main() {
  group('StatusBanner Widget Tests', () {
    testWidgets('renders active status correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBanner(status: TrackingStatus.active),
          ),
        ),
      );

      expect(find.text('Sistema activo'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('renders offline status correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBanner(status: TrackingStatus.offline),
          ),
        ),
      );

      expect(find.text('Sin conexión. Se guardan ubicaciones en el dispositivo.'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('renders custom message', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBanner(
              status: TrackingStatus.error,
              message: 'Custom Error Message',
            ),
          ),
        ),
      );

      expect(find.text('Custom Error Message'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('shows retry button and triggers callback', (WidgetTester tester) async {
      bool retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBanner(
              status: TrackingStatus.error,
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(retried, true);
    });

    testWidgets('shows settings button and triggers callback', (WidgetTester tester) async {
      bool settingsOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBanner(
              status: TrackingStatus.active,
              onOpenSettings: () => settingsOpened = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.settings), findsOneWidget);
      await tester.tap(find.byIcon(Icons.settings));
      expect(settingsOpened, true);
    });
  });
}
