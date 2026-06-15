import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/map/widgets/history_list.dart';
import 'package:flutter_application_1/models/location_point.dart';

void main() {
  group('HistoryList Widget Tests', () {
    final points = [
      LocationPoint(latitude: 10, longitude: 20, timestamp: DateTime.now()),
      LocationPoint(latitude: 11, longitude: 21, timestamp: DateTime.now()),
    ];

    testWidgets('renders list of items', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryList(
              items: points,
              isLoading: false,
            ),
          ),
        ),
      );

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Lat: 10.00000, Lng: 20.00000'), findsOneWidget);
    });

    testWidgets('renders empty state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryList(
              items: [],
              isLoading: false,
            ),
          ),
        ),
      );

      expect(find.text('Sin ubicaciones en el rango seleccionado'), findsOneWidget);
    });

    testWidgets('renders loading state when empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryList(
              items: [],
              isLoading: true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sin ubicaciones en el rango seleccionado'), findsNothing);
    });

    testWidgets('renders loading indicator at bottom when list is not empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryList(
              items: points,
              isLoading: true,
            ),
          ),
        ),
      );

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders error state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryList(
              items: [],
              isLoading: false,
              error: 'Failed to load',
            ),
          ),
        ),
      );

      expect(find.text('Failed to load'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('triggers onLoadMore when scrolling to bottom', (WidgetTester tester) async {
      bool loadMoreCalled = false;
      // Create enough items to force scrolling
      final manyPoints = List.generate(20, (i) => LocationPoint(latitude: i.toDouble(), longitude: i.toDouble(), timestamp: DateTime.now()));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryList(
              items: manyPoints,
              isLoading: false,
              onLoadMore: () => loadMoreCalled = true,
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();

      expect(loadMoreCalled, true);
    });

    testWidgets('triggers onSelect when item tapped', (WidgetTester tester) async {
      LocationPoint? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryList(
              items: points,
              isLoading: false,
              onSelect: (p) => selected = p,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Lat: 10.00000, Lng: 20.00000'));
      expect(selected, points[0]);
    });
  });
}
