import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/location_point.dart';
import 'package:flutter_application_1/screens/map/controllers/tracking_controller.dart';
import 'package:flutter_application_1/services/identity_service.dart';
import 'package:flutter_application_1/services/location_service.dart';
import 'package:flutter_application_1/services/location_sync_manager.dart';
import 'package:flutter_application_1/services/telemetry_log_service.dart';

class _FakeLocationService extends LocationService {}

class _FakeLocationSyncManager extends LocationSyncManager {
  _FakeLocationSyncManager();

  int queueCalls = 0;
  String? lastUid;
  LocationPoint? lastPoint;
  int? lastBatteryLevel;
  String? lastActivityType;

  @override
  Future<void> queueLocation({
    required String firebaseUid,
    required LocationPoint point,
    int? batteryLevel,
    String? activityType,
  }) async {
    queueCalls++;
    lastUid = firebaseUid;
    lastPoint = point;
    lastBatteryLevel = batteryLevel;
    lastActivityType = activityType;
  }
}

class _FakeTelemetryLogService extends TelemetryLogService {
  final List<String> messages = <String>[];

  @override
  Future<void> log(String message) async {
    messages.add(message);
  }
}

void main() {
  late _FakeLocationSyncManager syncManager;
  late _FakeTelemetryLogService telemetry;
  late TrackingController controller;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GetIt.I.allowReassignment = true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.I.reset();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    syncManager = _FakeLocationSyncManager();
    telemetry = _FakeTelemetryLogService();

    GetIt.I.registerSingleton<IdentityService>(IdentityService());
    GetIt.I.registerSingleton<TelemetryLogService>(telemetry);

    controller = TrackingController(
      locationService: _FakeLocationService(),
      syncManager: syncManager,
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    GetIt.I.reset();
  });

  test('processLocationUpdate encola en modo Flutter normal', () async {
    final point = LocationPoint(
      latitude: -12.1,
      longitude: -77.0,
      timestamp: DateTime.now(),
      accuracy: 5,
    );

    controller.updateTrackingFilters(nativeAlwaysOn: false, notify: false);

    await controller.processLocationUpdate(
      firebaseUid: 'uid-1',
      point: point,
      batteryLevel: 88,
      activityType: 'walking',
    );

    expect(syncManager.queueCalls, 1);
    expect(syncManager.lastUid, 'uid-1');
    expect(syncManager.lastPoint, same(point));
    expect(syncManager.lastBatteryLevel, 88);
    expect(syncManager.lastActivityType, 'walking');
  });

  test('processLocationUpdate no encola en modo nativo exclusivo Android', () async {
    final point = LocationPoint(
      latitude: -12.2,
      longitude: -77.1,
      timestamp: DateTime.now(),
      accuracy: 5,
    );

    controller.updateTrackingFilters(nativeAlwaysOn: true, notify: false);

    await controller.processLocationUpdate(
      firebaseUid: 'uid-2',
      point: point,
      batteryLevel: 50,
      activityType: 'unknown',
    );

    expect(syncManager.queueCalls, 0);
    expect(
      telemetry.messages.any((msg) => msg.contains('Punto GPS (modo nativo)')),
      isTrue,
    );
  });
}
