import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/map/controllers/map_screen_controller.dart';
import 'package:flutter_application_1/screens/map/widgets/status_banner.dart';
import 'package:flutter_application_1/models/assigned_visit.dart';
import 'package:flutter_application_1/models/location_point.dart';

void main() {
  group('MapScreenController Tests', () {
    late MapScreenController controller;

    setUp(() {
      controller = MapScreenController();
    });

    test('Initial state is correct', () {
      expect(controller.isTracking, false);
      expect(controller.waitingInitialFix, false);
      expect(controller.isLoading, true);
      expect(controller.mapReady, false);
      expect(controller.backendReady, false);
      expect(controller.showingHistory, false);
      expect(controller.trackingStatus, TrackingStatus.idle);
    });

    test('setTrackingState updates state and notifies listeners', () {
      bool notified = false;
      controller.addListener(() => notified = true);

      controller.setTrackingState(isTracking: true, waitingInitialFix: true);

      expect(controller.isTracking, true);
      expect(controller.waitingInitialFix, true);
      expect(controller.trackingStatus, TrackingStatus.syncing);
      expect(notified, true);
    });

    test('setConnectionMessage updates state and notifies listeners', () {
      controller.setConnectionMessage('No internet');
      expect(controller.connectionMessage, 'No internet');
      expect(controller.trackingStatus, TrackingStatus.offline);
    });

    test('setShutdownMessage updates state and notifies listeners', () {
      controller.setShutdownMessage('App closing');
      expect(controller.shutdownMessage, 'App closing');
      expect(controller.trackingStatus, TrackingStatus.error);
    });

    test('clearMessages resets messages', () {
      controller.setConnectionMessage('Error');
      controller.setShutdownMessage('Error');
      controller.clearMessages();
      expect(controller.connectionMessage, null);
      expect(controller.shutdownMessage, null);
    });

    test('setVisits updates visits and index', () {
      final visits = [
        AssignedVisit(id: '1', name: 'Visit 1', address: 'Addr 1', latitude: 0, longitude: 0, scheduledAt: DateTime.now()),
        AssignedVisit(id: '2', name: 'Visit 2', address: 'Addr 2', latitude: 0, longitude: 0, scheduledAt: DateTime.now()),
      ];

      controller.setVisits(visits, currentIndex: 1);

      expect(controller.todayVisits, visits);
      expect(controller.currentVisitIndex, 1);
    });

    test('markVisitCompleted adds id to set', () {
       final visits = [
        AssignedVisit(id: '1', name: 'Visit 1', address: 'Addr 1', latitude: 0, longitude: 0, scheduledAt: DateTime.now()),
      ];
      controller.setVisits(visits);

      controller.markVisitCompleted(0);
      expect(controller.completedVisitIds.contains('1'), true);
    });

    test('updateLastFix updates location info', () {
      final point = LocationPoint(
        latitude: 10,
        longitude: 20,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        speed: 10.0,
      );

      controller.updateLastFix(point);

      expect(controller.lastKnownAccuracy, 5.0);
      expect(controller.lastKnownSpeed, 10.0);
      expect(controller.lastFixAt, point.timestamp);
    });

    test('UI state setters update values', () {
      controller.setIsLoading(false);
      expect(controller.isLoading, false);

      controller.setMapReady(true);
      expect(controller.mapReady, true);

      controller.setBackendReady(true);
      expect(controller.backendReady, true);

      controller.setShowingHistory(true);
      expect(controller.showingHistory, true);
    });
  });
}
