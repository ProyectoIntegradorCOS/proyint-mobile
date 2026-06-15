import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/map/controllers/app_lifecycle_manager.dart';
import 'package:flutter_application_1/screens/map/controllers/map_screen_controller.dart';
import 'package:flutter_application_1/screens/map/controllers/tracking_controller.dart';
import 'package:flutter_application_1/services/api_service.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/identity_service.dart';
import 'package:flutter_application_1/services/location_service.dart';
import 'package:flutter_application_1/services/location_sync_manager.dart';
import 'package:flutter_application_1/services/telemetry_log_service.dart';

import '../../../api_client_test.mocks.dart';

class _FakeLocationService extends LocationService {}

class _FakeLocationSyncManager extends LocationSyncManager {}

class _FakeApiService extends ApiService {
  String? updatedToken;

  @override
  Future<void> updateAuthToken(String? token) async {
    updatedToken = token;
  }
}

class _FakeTelemetryLogService extends TelemetryLogService {
  final List<String> messages = <String>[];

  @override
  Future<void> log(String message) async {
    messages.add(message);
  }
}

class _TestTrackingController extends TrackingController {
  _TestTrackingController()
      : super(
          locationService: _FakeLocationService(),
          syncManager: _FakeLocationSyncManager(),
        );

  bool fakeIsTracking = false;
  bool fakeWaitingInitialFix = false;
  bool fakeNativeAlwaysOn = false;
  bool startResult = true;
  bool allowNextStalePointCalled = false;
  bool startTrackingCalled = false;
  bool stopTrackingCalled = false;
  bool? stopNativeTrackingArg;
  bool? markForegroundTrackingInactiveArg;

  @override
  bool get isTracking => fakeIsTracking;

  @override
  bool get waitingInitialFix => fakeWaitingInitialFix;

  @override
  bool get nativeAlwaysOn => fakeNativeAlwaysOn;

  @override
  void allowNextStalePoint() {
    allowNextStalePointCalled = true;
  }

  @override
  Future<bool> startTracking({
    required Function(String) onError,
    required Function() onOutsideSchedule,
    bool enforceEndHour = false,
  }) async {
    startTrackingCalled = true;
    fakeIsTracking = startResult;
    fakeWaitingInitialFix = false;
    return startResult;
  }

  @override
  Future<void> stopTracking({
    bool stopNativeTracking = true,
    bool markForegroundTrackingInactive = true,
  }) async {
    stopTrackingCalled = true;
    stopNativeTrackingArg = stopNativeTracking;
    markForegroundTrackingInactiveArg = markForegroundTrackingInactive;
    fakeIsTracking = false;
    fakeWaitingInitialFix = false;
  }
}

Future<void> _drainMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  const backgroundChannel = MethodChannel('pe.gob.onp.thaqhiri/background_schedule');
  const secureStoreChannel = MethodChannel('pe.gob.onp.thaqhiri/secure_store');

  late _TestTrackingController trackingController;
  late MapScreenController stateController;
  late _FakeApiService apiService;
  late _FakeTelemetryLogService telemetry;
  late MockAuthService authService;
  late List<String> channelCalls;
  late int startBackgroundFlushTimerCalls;
  late int stopBackgroundFlushTimerCalls;
  late int startTokenRefreshTimerCalls;
  late int hydrateRouteCalls;
  late int refreshPendingRouteCalls;
  late List<String> notifyMessages;
  late List<String> errorMessages;
  late int outsideScheduleCalls;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GetIt.I.allowReassignment = true;
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'bg_flush_last_at': '2026-03-12T15:34:58-05:00',
      'bg_flush_last_status': 'ok',
      'bg_hora_inicio': 8,
      'bg_hora_fin': 17,
      'native_sqlite_count': 3,
    });

    await GetIt.I.reset();
    GetIt.I.registerSingleton<IdentityService>(IdentityService());
    channelCalls = <String>[];
    startBackgroundFlushTimerCalls = 0;
    stopBackgroundFlushTimerCalls = 0;
    startTokenRefreshTimerCalls = 0;
    hydrateRouteCalls = 0;
    refreshPendingRouteCalls = 0;
    notifyMessages = <String>[];
    errorMessages = <String>[];
    outsideScheduleCalls = 0;

    trackingController = _TestTrackingController();
    stateController = MapScreenController();
    apiService = _FakeApiService();
    telemetry = _FakeTelemetryLogService();
    authService = MockAuthService();

    GetIt.I.registerSingleton<TelemetryLogService>(telemetry);
    GetIt.I.registerSingleton<AuthService>(authService);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backgroundChannel, (call) async {
      channelCalls.add(call.method);
      return switch (call.method) {
        'startNativeTracking' => null,
        'schedulePendingFlush' => null,
        'cancelPendingFlush' => null,
        'setForegroundTrackingActive' => null,
        'enforceNow' => null,
        _ => null,
      };
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStoreChannel, (call) async => null);
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backgroundChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStoreChannel, null);
    await GetIt.I.reset();
  });

  AppLifecycleManager buildManager() {
    return AppLifecycleManager(
      trackingController: trackingController,
      stateController: stateController,
      apiService: apiService,
      onStartBackgroundFlushTimer: () => startBackgroundFlushTimerCalls++,
      onStopBackgroundFlushTimer: () => stopBackgroundFlushTimerCalls++,
      onStartTokenRefreshTimer: () => startTokenRefreshTimerCalls++,
      onHydrateRouteFromBackground: () async => hydrateRouteCalls++,
      onRefreshPendingRouteFromLocal: () async => refreshPendingRouteCalls++,
      onNotifyTrackingModeSwitch: notifyMessages.add,
      onError: errorMessages.add,
      onOutsideSchedule: () => outsideScheduleCalls++,
      getEnforceEndHour: () => false,
    );
  }

  test('pausing app delegates tracking to native and starts background timers', () async {
    final manager = buildManager();
    trackingController.fakeIsTracking = true;
    trackingController.fakeNativeAlwaysOn = false;

    manager.didChangeAppLifecycleState(AppLifecycleState.paused);
    await _drainMicrotasks();

    expect(manager.isInForeground, isFalse);
    expect(notifyMessages, contains('app en segundo plano'));
    expect(trackingController.stopTrackingCalled, isTrue);
    expect(trackingController.stopNativeTrackingArg, isFalse);
    expect(trackingController.markForegroundTrackingInactiveArg, isFalse);
    expect(startBackgroundFlushTimerCalls, 1);
    expect(channelCalls, containsAll(<String>[
      'setForegroundTrackingActive',
      'startNativeTracking',
      'schedulePendingFlush',
      'enforceNow',
    ]));
    expect(stateController.isTracking, isFalse);
    expect(stateController.waitingInitialFix, isFalse);
  });

  test('resuming app restores session, refreshes route and restarts Flutter tracking', () async {
    final manager = buildManager();
    trackingController.fakeIsTracking = true;

    manager.didChangeAppLifecycleState(AppLifecycleState.paused);
    await _drainMicrotasks();

    channelCalls.clear();
    trackingController.startTrackingCalled = false;
    when(authService.restoreSession()).thenAnswer((_) async {});
    when(authService.ensureValidToken()).thenAnswer((_) async => 'renewed-token');

    manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drainMicrotasks();

    expect(manager.isInForeground, isTrue);
    expect(notifyMessages, contains('app en primer plano'));
    expect(trackingController.allowNextStalePointCalled, isTrue);
    expect(hydrateRouteCalls, 1);
    expect(refreshPendingRouteCalls, 1);
    expect(apiService.updatedToken, 'renewed-token');
    expect(trackingController.startTrackingCalled, isTrue);
    expect(startTokenRefreshTimerCalls, 1);
    expect(stopBackgroundFlushTimerCalls, 1);
    expect(channelCalls, containsAll(<String>[
      'cancelPendingFlush',
      'setForegroundTrackingActive',
      'enforceNow',
    ]));
    expect(stateController.isTracking, isTrue);
    expect(stateController.waitingInitialFix, isFalse);
  });
}
