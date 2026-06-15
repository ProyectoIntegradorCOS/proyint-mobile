import Flutter
import CoreLocation
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  private let suiteName = "RunnerTests.BackgroundScheduleChannel"

  override func tearDown() {
    let defaults = UserDefaults(suiteName: suiteName)
    defaults?.removePersistentDomain(forName: suiteName)
    SecureStoreChannel.resetHandlers()
    super.tearDown()
  }

  func testShouldTrackReturnsTrueWithinWeekdayWindow() {
    let defaults = makeDefaults()
    defaults.set(8, forKey: "flutter.bg_hora_inicio")
    defaults.set(20, forKey: "flutter.bg_hora_fin")

    let shouldTrack = BackgroundScheduleChannel.shouldTrack(
      at: makeDate(year: 2026, month: 3, day: 10, hour: 9),
      defaults: defaults,
      timeZone: limaTimeZone
    )

    XCTAssertTrue(shouldTrack)
  }

  func testShouldTrackReturnsFalseOutsideConfiguredHours() {
    let defaults = makeDefaults()
    defaults.set(8, forKey: "flutter.bg_hora_inicio")
    defaults.set(20, forKey: "flutter.bg_hora_fin")

    let shouldTrack = BackgroundScheduleChannel.shouldTrack(
      at: makeDate(year: 2026, month: 3, day: 10, hour: 21),
      defaults: defaults,
      timeZone: limaTimeZone
    )

    XCTAssertFalse(shouldTrack)
  }

  func testShouldTrackReturnsFalseOnWeekend() {
    let defaults = makeDefaults()
    defaults.set(8, forKey: "flutter.bg_hora_inicio")
    defaults.set(20, forKey: "flutter.bg_hora_fin")

    let shouldTrack = BackgroundScheduleChannel.shouldTrack(
      at: makeDate(year: 2026, month: 3, day: 14, hour: 10),
      defaults: defaults,
      timeZone: limaTimeZone
    )

    XCTAssertFalse(shouldTrack)
  }

  func testValidatedTokenReturnsNilForMissingOrEmptyToken() {
    XCTAssertNil(SecureStoreChannel.validatedToken(from: nil))
    XCTAssertNil(SecureStoreChannel.validatedToken(from: [:]))
    XCTAssertNil(SecureStoreChannel.validatedToken(from: ["token": ""]))
  }

  func testHandleSetTokenReturnsInvalidArgsWhenTokenIsMissing() {
    let expectation = expectation(description: "setToken invalid args")

    SecureStoreChannel.handle(
      call: FlutterMethodCall(methodName: "setToken", arguments: [:])
    ) { result in
      let error = result as? FlutterError
      XCTAssertEqual(error?.code, "invalid_args")
      expectation.fulfill()
    }

    waitForExpectations(timeout: 1)
  }

  func testHandleSetTokenPersistsTokenUsingInjectedHandler() {
    let expectation = expectation(description: "setToken success")
    var capturedToken: String?
    SecureStoreChannel.writeTokenHandler = { token in
      capturedToken = token
    }

    SecureStoreChannel.handle(
      call: FlutterMethodCall(
        methodName: "setToken",
        arguments: ["token": "abc123"]
      )
    ) { result in
      XCTAssertNil(result)
      expectation.fulfill()
    }

    waitForExpectations(timeout: 1)
    XCTAssertEqual(capturedToken, "abc123")
  }

  func testHandleClearTokenInvokesInjectedHandler() {
    let expectation = expectation(description: "clearToken success")
    var clearCalled = false
    SecureStoreChannel.clearTokenHandler = {
      clearCalled = true
    }

    SecureStoreChannel.handle(
      call: FlutterMethodCall(methodName: "clearToken", arguments: nil)
    ) { result in
      XCTAssertNil(result)
      expectation.fulfill()
    }

    waitForExpectations(timeout: 1)
    XCTAssertTrue(clearCalled)
  }

  func testNormalizedApiBaseUrlTrimsWhitespaceAndTrailingSlash() {
    let normalized = PendingFlushService.normalizedApiBaseUrl(" https://api.onp.gob.pe/ ")
    XCTAssertEqual(normalized, "https://api.onp.gob.pe")
  }

  func testMakeFlushContextBuildsContextWhenDependenciesExist() {
    let defaults = makeDefaults()
    defaults.set("uid-123", forKey: "flutter.auth_uid")
    defaults.set(" https://api.onp.gob.pe/ ", forKey: "flutter.api_base_url")

    let context = PendingFlushService.makeFlushContext(
      defaults: defaults,
      tokenReader: { "token-abc" },
      dbPathProvider: { "/tmp/tracking_store.db" }
    )

    XCTAssertEqual(context?.uid, "uid-123")
    XCTAssertEqual(context?.apiBaseUrl, "https://api.onp.gob.pe")
    XCTAssertEqual(context?.token, "token-abc")
    XCTAssertEqual(context?.dbPath, "/tmp/tracking_store.db")
  }

  func testMakeFlushContextReturnsNilWhenApiBaseUrlIsMissing() {
    let defaults = makeDefaults()
    defaults.set("uid-123", forKey: "flutter.auth_uid")

    let context = PendingFlushService.makeFlushContext(
      defaults: defaults,
      tokenReader: { "token-abc" },
      dbPathProvider: { "/tmp/tracking_store.db" }
    )

    XCTAssertNil(context)
  }

  func testRequestPayloadMapsPendingRowsToApiShape() {
    let payload = PendingFlushService.requestPayload(
      for: [
        PendingFlushService.PendingRow(
          id: 7,
          saaSubject: "uid-123",
          latitude: -12.0464,
          longitude: -77.0428,
          timestamp: "2026-03-12T10:15:00-05:00",
          accuracy: 8.5,
          altitude: 120.0,
          speed: 1.2,
          heading: 35.0,
          batteryLevel: 87.0,
          activityType: "walking"
        )
      ]
    )

    let first = payload.first
    XCTAssertEqual(first?["saaSubject"] as? String, "uid-123")
    XCTAssertEqual(first?["latitude"] as? Double, -12.0464)
    XCTAssertEqual(first?["longitude"] as? Double, -77.0428)
    XCTAssertEqual(first?["batteryLevel"] as? Int, 87)
    XCTAssertEqual(first?["activityType"] as? String, "walking")
  }

  func testMakeBatchUrlAppendsLocationsBatchPath() {
    let url = PendingFlushService.makeBatchUrl(
      apiBaseUrl: " https://api.onp.gob.pe/base/ "
    )

    XCTAssertEqual(url?.absoluteString, "https://api.onp.gob.pe/base/locations/batch")
  }

  func testMakeBatchRequestBuildsJsonPostRequest() throws {
    let locations = [
      PendingFlushService.PendingRow(
        id: 1,
        saaSubject: "uid-123",
        latitude: -12.0464,
        longitude: -77.0428,
        timestamp: "2026-03-12T10:15:00-05:00",
        accuracy: 8.5,
        altitude: 120.0,
        speed: 1.2,
        heading: 35.0,
        batteryLevel: 87.0,
        activityType: "walking"
      )
    ]

    let request = PendingFlushService.makeBatchRequest(
      apiBaseUrl: "https://api.onp.gob.pe/",
      token: "token-abc",
      locations: locations
    )

    XCTAssertEqual(request?.url?.absoluteString, "https://api.onp.gob.pe/locations/batch")
    XCTAssertEqual(request?.httpMethod, "POST")
    XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "application/json")
    XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer token-abc")

    let body = try XCTUnwrap(request?.httpBody)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    let payload = try XCTUnwrap(json["locations"] as? [[String: Any]])
    XCTAssertEqual(payload.count, 1)
    XCTAssertEqual(payload.first?["saaSubject"] as? String, "uid-123")
  }

  func testIsAcceptedAccuracyAcceptsOnlyValuesWithinThreshold() {
    XCTAssertTrue(LocationTracker.isAcceptedAccuracy(0))
    XCTAssertTrue(LocationTracker.isAcceptedAccuracy(25))
    XCTAssertTrue(LocationTracker.isAcceptedAccuracy(50))
    XCTAssertFalse(LocationTracker.isAcceptedAccuracy(-1))
    XCTAssertFalse(LocationTracker.isAcceptedAccuracy(50.1))
  }

  func testLocationTrackerIsWithinScheduleUsesSharedScheduleLogic() {
    let defaults = makeDefaults()
    defaults.set(8, forKey: "flutter.bg_hora_inicio")
    defaults.set(20, forKey: "flutter.bg_hora_fin")

    let weekdayDate = makeDate(year: 2026, month: 3, day: 11, hour: 10)
    let weekendDate = makeDate(year: 2026, month: 3, day: 15, hour: 10)

    XCTAssertTrue(LocationTracker.isWithinSchedule(at: weekdayDate, defaults: defaults))
    XCTAssertFalse(LocationTracker.isWithinSchedule(at: weekendDate, defaults: defaults))
  }

  func testMakePointNormalizesNegativeSpeedAndHeading() {
    let location = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: -12.0464, longitude: -77.0428),
      altitude: 120,
      horizontalAccuracy: 7.5,
      verticalAccuracy: 4.0,
      course: -1,
      speed: -1,
      timestamp: makeDate(year: 2026, month: 3, day: 12, hour: 10)
    )

    let point = LocationTracker.makePoint(from: location, timeZone: limaTimeZone)

    XCTAssertEqual(point["latitude"] as? Double, -12.0464)
    XCTAssertEqual(point["longitude"] as? Double, -77.0428)
    XCTAssertEqual(point["accuracy"] as? Double, 7.5)
    XCTAssertEqual(point["speed"] as? Double, 0)
    XCTAssertEqual(point["heading"] as? Double, 0)
    XCTAssertEqual(point["source"] as? String, "native_ios")
    XCTAssertNotNil(point["timestamp"] as? String)
  }

  func testShouldDeliverToSinkDependsOnFlutterAppStateAndSinkPresence() {
    XCTAssertTrue(
      LocationTracker.shouldDeliverToSink(
        isFlutterActive: false,
        appIsActive: true,
        hasEventSink: true
      )
    )
    XCTAssertFalse(
      LocationTracker.shouldDeliverToSink(
        isFlutterActive: true,
        appIsActive: true,
        hasEventSink: true
      )
    )
    XCTAssertFalse(
      LocationTracker.shouldDeliverToSink(
        isFlutterActive: false,
        appIsActive: false,
        hasEventSink: true
      )
    )
    XCTAssertFalse(
      LocationTracker.shouldDeliverToSink(
        isFlutterActive: false,
        appIsActive: true,
        hasEventSink: false
      )
    )
  }

  func testResolveTrackingUidReturnsStoredValueOrEmptyString() {
    let defaults = makeDefaults()
    XCTAssertEqual(LocationTracker.resolveTrackingUid(defaults: defaults), "")

    defaults.set("tracking-uid-1", forKey: "flutter.tracking_uid")
    XCTAssertEqual(
      LocationTracker.resolveTrackingUid(defaults: defaults),
      "tracking-uid-1"
    )
  }

  func testStartActionRequestsAlwaysWhenStatusIsNotDetermined() {
    XCTAssertEqual(
      LocationTracker.startAction(
        authorizationStatus: .notDetermined,
        isFlutterActive: false
      ),
      .requestAlwaysAuthorization
    )
  }

  func testStartActionRequestsAlwaysWhenStatusIsWhenInUse() {
    XCTAssertEqual(
      LocationTracker.startAction(
        authorizationStatus: .authorizedWhenInUse,
        isFlutterActive: false
      ),
      .requestAlwaysAuthorization
    )
  }

  func testStartActionStartsTrackingWhenAlwaysAuthorized() {
    XCTAssertEqual(
      LocationTracker.startAction(
        authorizationStatus: .authorizedAlways,
        isFlutterActive: false
      ),
      .startUpdatingLocation
    )
  }

  func testStartActionNoOpsWhenFlutterIsActive() {
    XCTAssertEqual(
      LocationTracker.startAction(
        authorizationStatus: .authorizedAlways,
        isFlutterActive: true
      ),
      .noOp
    )
  }

  func testAuthorizationTransitionStartsTrackingAfterAlwaysGrant() {
    XCTAssertEqual(
      LocationTracker.authorizationTransition(
        authorizationStatus: .authorizedAlways,
        shouldStartWhenAuthorized: true,
        isTracking: false
      ),
      .startTracking
    )
  }

  func testAuthorizationTransitionKeepsWaitingWhenOnlyWhenInUse() {
    XCTAssertEqual(
      LocationTracker.authorizationTransition(
        authorizationStatus: .authorizedWhenInUse,
        shouldStartWhenAuthorized: true,
        isTracking: false
      ),
      .keepWaitingForAlways
    )
  }

  func testAuthorizationTransitionStopsWhenDenied() {
    XCTAssertEqual(
      LocationTracker.authorizationTransition(
        authorizationStatus: .denied,
        shouldStartWhenAuthorized: false,
        isTracking: true
      ),
      .stopTracking
    )
  }

  func testAuthorizationTransitionRefreshesWhenAlreadyTrackingAndAlwaysAuthorized() {
    XCTAssertEqual(
      LocationTracker.authorizationTransition(
        authorizationStatus: .authorizedAlways,
        shouldStartWhenAuthorized: false,
        isTracking: true
      ),
      .refreshTracking
    )
  }

  func testStartRequestsAlwaysAuthorizationOnNotDeterminedStatus() {
    let manager = FakeLocationManager(status: .notDetermined)
    let tracker = LocationTracker(locationManager: manager)

    tracker.start()

    XCTAssertEqual(manager.requestAlwaysAuthorizationCallCount, 1)
    XCTAssertEqual(manager.startUpdatingLocationCallCount, 0)
  }

  func testStartBeginsLocationUpdatesWhenAlwaysAuthorized() {
    let manager = FakeLocationManager(status: .authorizedAlways)
    let tracker = LocationTracker(locationManager: manager)

    tracker.start()

    XCTAssertEqual(manager.startUpdatingLocationCallCount, 1)
    XCTAssertEqual(manager.requestAlwaysAuthorizationCallCount, 0)
  }

  func testStopStopsLocationUpdates() {
    let manager = FakeLocationManager(status: .authorizedAlways)
    let tracker = LocationTracker(locationManager: manager)

    tracker.stop()

    XCTAssertEqual(manager.stopUpdatingLocationCallCount, 1)
  }

  func testAuthorizationChangeStartsTrackingAfterAlwaysGrant() {
    let manager = FakeLocationManager(status: .notDetermined)
    let tracker = LocationTracker(locationManager: manager)
    tracker.start()

    manager.status = .authorizedAlways
    tracker.locationManagerDidChangeAuthorization(CLLocationManager())

    XCTAssertEqual(manager.startUpdatingLocationCallCount, 1)
  }

  func testAuthorizationChangeStopsTrackingWhenDenied() {
    let manager = FakeLocationManager(status: .authorizedAlways)
    let tracker = LocationTracker(locationManager: manager)
    tracker.start()
    manager.status = .denied

    tracker.locationManagerDidChangeAuthorization(CLLocationManager())

    XCTAssertEqual(manager.stopUpdatingLocationCallCount, 1)
  }

  func testDispatchPointSendsToSinkWhenAppIsActiveAndFlutterIsInactive() {
    let point: [String: Any] = ["latitude": -12.0]
    var deliveredPoint: [String: Any]?
    var enqueueCallCount = 0

    LocationTracker.dispatchPoint(
      point: point,
      isFlutterActive: false,
      appIsActive: true,
      eventSink: { event in
        deliveredPoint = event as? [String: Any]
      },
      enqueuePoint: { _ in
        enqueueCallCount += 1
      }
    )

    XCTAssertEqual(deliveredPoint?["latitude"] as? Double, -12.0)
    XCTAssertEqual(enqueueCallCount, 0)
  }

  func testDispatchPointEnqueuesWhenAppIsInBackground() {
    let point: [String: Any] = ["latitude": -12.0]
    var enqueuedPoint: [String: Any]?

    LocationTracker.dispatchPoint(
      point: point,
      isFlutterActive: false,
      appIsActive: false,
      eventSink: { _ in
        XCTFail("No debe enviar al sink en background")
      },
      enqueuePoint: { point in
        enqueuedPoint = point
      }
    )

    XCTAssertEqual(enqueuedPoint?["latitude"] as? Double, -12.0)
  }

  func testDispatchPointEnqueuesWhenThereIsNoSink() {
    let point: [String: Any] = ["latitude": -12.0]
    var enqueuedPoint: [String: Any]?

    LocationTracker.dispatchPoint(
      point: point,
      isFlutterActive: false,
      appIsActive: true,
      eventSink: nil,
      enqueuePoint: { point in
        enqueuedPoint = point
      }
    )

    XCTAssertEqual(enqueuedPoint?["latitude"] as? Double, -12.0)
  }

  func testDispatchPointDoesNothingWhenFlutterIsActive() {
    let point: [String: Any] = ["latitude": -12.0]
    var enqueueCallCount = 0
    var sinkCallCount = 0

    LocationTracker.dispatchPoint(
      point: point,
      isFlutterActive: true,
      appIsActive: true,
      eventSink: { _ in
        sinkCallCount += 1
      },
      enqueuePoint: { _ in
        enqueueCallCount += 1
      }
    )

    XCTAssertEqual(sinkCallCount, 0)
    XCTAssertEqual(enqueueCallCount, 0)
  }

  private var limaTimeZone: TimeZone {
    TimeZone(identifier: "America/Lima") ?? .current
  }

  private func makeDefaults() -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      fatalError("No se pudo crear UserDefaults de prueba")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = limaTimeZone
    let components = DateComponents(
      timeZone: limaTimeZone,
      year: year,
      month: month,
      day: day,
      hour: hour
    )
    guard let date = calendar.date(from: components) else {
      fatalError("No se pudo construir la fecha de prueba")
    }
    return date
  }
}

private final class FakeLocationManager: LocationManaging {
  var delegate: CLLocationManagerDelegate?
  var desiredAccuracy: CLLocationAccuracy = 0
  var distanceFilter: CLLocationDistance = 0
  var pausesLocationUpdatesAutomatically = false
  var activityType: CLActivityType = .other
  var allowsBackgroundLocationUpdates = false

  var status: CLAuthorizationStatus
  private(set) var requestAlwaysAuthorizationCallCount = 0
  private(set) var startUpdatingLocationCallCount = 0
  private(set) var stopUpdatingLocationCallCount = 0

  init(status: CLAuthorizationStatus) {
    self.status = status
  }

  func requestAlwaysAuthorization() {
    requestAlwaysAuthorizationCallCount += 1
  }

  func startUpdatingLocation() {
    startUpdatingLocationCallCount += 1
  }

  func stopUpdatingLocation() {
    stopUpdatingLocationCallCount += 1
  }

  func currentAuthorizationStatus() -> CLAuthorizationStatus {
    status
  }
}
