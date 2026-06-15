// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/locator.dart';

void main() {
  setUp(() async {
    await GetIt.I.reset();
    setupLocator();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Ajusta smoke test al widget raíz actual del app][obj: widget_test]
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LocationTrackerApp());
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Avanza el tiempo para consumir el Timer del SplashScreen y evitar timers pendientes][obj: widget_test SplashScreen timer]
    await tester.pump(const Duration(seconds: 2));

    // Verify that the app loads (this is a basic smoke test)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
