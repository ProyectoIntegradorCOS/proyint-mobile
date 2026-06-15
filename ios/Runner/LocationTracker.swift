// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:51 UTC-5 (Lima)][desc: Tracker nativo iOS con CLLocationManager, validación horaria interna (L-V, hora Lima) y cola UserDefaults para resiliencia ante suspensión del engine Flutter][obj: LocationTracker]
import CoreLocation
import Flutter
import Foundation
import UIKit
import UserNotifications

protocol LocationManaging: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var activityType: CLActivityType { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }

    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func currentAuthorizationStatus() -> CLAuthorizationStatus
}

final class SystemLocationManager: LocationManaging {
    private let manager = CLLocationManager()

    var delegate: CLLocationManagerDelegate? {
        get { manager.delegate }
        set { manager.delegate = newValue }
    }

    var desiredAccuracy: CLLocationAccuracy {
        get { manager.desiredAccuracy }
        set { manager.desiredAccuracy = newValue }
    }

    var distanceFilter: CLLocationDistance {
        get { manager.distanceFilter }
        set { manager.distanceFilter = newValue }
    }

    var pausesLocationUpdatesAutomatically: Bool {
        get { manager.pausesLocationUpdatesAutomatically }
        set { manager.pausesLocationUpdatesAutomatically = newValue }
    }

    var activityType: CLActivityType {
        get { manager.activityType }
        set { manager.activityType = newValue }
    }

    var allowsBackgroundLocationUpdates: Bool {
        get { manager.allowsBackgroundLocationUpdates }
        set { manager.allowsBackgroundLocationUpdates = newValue }
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    func currentAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }
}

fileprivate struct LocationEventQueueStore {
    let defaults: UserDefaults
    let queueKey: String

    func load() -> [[String: Any]] {
        defaults.array(forKey: queueKey) as? [[String: Any]] ?? []
    }

    func append(_ point: [String: Any]) {
        var queue = load()
        queue.append(point)
        defaults.set(queue, forKey: queueKey)
    }

    func clear() {
        defaults.removeObject(forKey: queueKey)
    }
}

fileprivate final class LocationEventBridge {
    private let queueStore: LocationEventQueueStore
    private var eventSink: FlutterEventSink?

    init(queueStore: LocationEventQueueStore) {
        self.queueStore = queueStore
    }

    func setEventSink(_ sink: FlutterEventSink?) {
        eventSink = sink
        if sink != nil {
            drainQueueIfPossible()
        }
    }

    func dispatchQueuedOrLivePoint(
        _ point: [String: Any],
        isFlutterActive: Bool,
        appIsActive: Bool,
        enqueueFallback: @escaping ([String: Any]) -> Void
    ) {
        LocationTracker.dispatchPoint(
            point: point,
            isFlutterActive: isFlutterActive,
            appIsActive: appIsActive,
            eventSink: eventSink,
            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Siempre escribe a SQLite en background (enqueueFallback→enqueue→PendingFlushService), sin importar si eventSink está activo. Antes iba a UserDefaults cuando eventSink==nil, perdiendo puntos si el engine Dart estaba pausado.][obj: LocationEventBridge.dispatchQueuedOrLivePoint enqueue sqlite]
            enqueuePoint: { point in
                enqueueFallback(point)
            }
        )
    }

    func drainQueueIfPossible() {
        guard let sink = eventSink else { return }
        let queue = queueStore.load()
        guard !queue.isEmpty else { return }

        NSLog("[LocationTracker] Drenando \(queue.count) puntos en cola")
        for point in queue {
            sink(point)
        }
        queueStore.clear()
    }
}

private struct LocationPointDispatcher {
    let isFlutterActive: Bool
    let appIsActiveProvider: () -> Bool
    let enqueuePoint: ([String: Any]) -> Void

    func dispatch(
        point: [String: Any],
        eventSink: FlutterEventSink?
    ) {
        guard !isFlutterActive else { return }

        if LocationTracker.shouldDeliverToSink(
            isFlutterActive: isFlutterActive,
            appIsActive: appIsActiveProvider(),
            hasEventSink: eventSink != nil
        ), let sink = eventSink {
            sink(point)
            return
        }

        enqueuePoint(point)
    }
}

class LocationTracker: NSObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()
    static let maxAccuracyMeters: Double = 50.0
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: En background iOS usa cell tower/WiFi en vez de GPS full; la accuracy típica es 50-500m. Umbral más relajado para no descartar todos los puntos en background.][obj: LocationTracker.maxBackgroundAccuracyMeters]
    static let maxBackgroundAccuracyMeters: Double = 200.0

    enum StartAction {
        case requestAlwaysAuthorization
        case startUpdatingLocation
        case deny
        case noOp
    }

    enum AuthorizationTransition {
        case startTracking
        case keepWaitingForAlways
        case stopTracking
        case refreshTracking
        case noOp
    }

    private let locationManager: LocationManaging
    private let eventBridge: LocationEventBridge
    private(set) var isTracking = false
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Conserva intención de arranque tras pedir permisos y evita duplicidad cuando Flutter foreground ya está capturando][obj: LocationTracker permission/tracker flags]
    private var shouldStartWhenAuthorized = false
    private var isFlutterActive = false

    fileprivate init(
        locationManager: LocationManaging = SystemLocationManager(),
        eventBridge: LocationEventBridge? = nil
    ) {
        self.locationManager = locationManager
        self.eventBridge = eventBridge ?? LocationEventBridge(
            queueStore: LocationEventQueueStore(
                defaults: .standard,
                queueKey: "pe.gob.onp.thaqhiri.location_queue"
            )
        )
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 10
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .other
        locationManager.allowsBackgroundLocationUpdates = true
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Drena cola UserDefaults cada vez que la app vuelve a foreground, no solo en cold start][obj: LocationTracker drainQueue on resume]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func onAppDidBecomeActive() {
        eventBridge.drainQueueIfPossible()
    }

    // MARK: - API pública (invocada desde AppDelegate vía MethodChannel)

    func setEventSink(_ sink: FlutterEventSink?) {
        eventBridge.setEventSink(sink)
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Exige permiso Always para tracking background iOS y reintenta arranque automático tras autorización][obj: LocationTracker.start permission flow]
    func start() {
        guard !isFlutterActive else {
            NSLog("[LocationTracker] Flutter foreground activo; no se inicia tracker nativo")
            return
        }

        let status = locationManager.currentAuthorizationStatus()
        let action = Self.startAction(
            authorizationStatus: status,
            isFlutterActive: isFlutterActive
        )
        switch action {
        case .requestAlwaysAuthorization:
            shouldStartWhenAuthorized = true
            locationManager.requestAlwaysAuthorization()
            if status == .authorizedWhenInUse {
                NSLog("[LocationTracker] Solicitando upgrade de permiso a Always")
            }
        case .startUpdatingLocation:
            shouldStartWhenAuthorized = false
            isTracking = true
            locationManager.startUpdatingLocation()
            NSLog("[LocationTracker] TRACKING_IOS_START")
        case .deny:
            NSLog("[LocationTracker] Sin permisos de ubicación, no se puede iniciar")
            isTracking = false
        case .noOp:
            return
        }
    }

    func stop() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        NSLog("[LocationTracker] TRACKING_IOS_STOP")
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Sincroniza si Flutter foreground está activo para evitar doble captura entre geolocator y tracker nativo][obj: LocationTracker.setFlutterActive]
    func setFlutterActive(_ active: Bool) {
        isFlutterActive = active
        if active {
            stop()
        }
    }

    func updateSettings(distanceFilter: Double, intervalSeconds: Int) {
        locationManager.distanceFilter = distanceFilter
        // CLLocationManager no tiene intervalDuration; la frecuencia mínima
        // se controla solo con distanceFilter en iOS.
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: En background iOS no usa GPS full; la accuracy típica es 50-500m. Se permite hasta 500m en background para no descartar todos los puntos.][obj: LocationTracker accuracy background]
        let appActive = Self.isApplicationActive()
        let maxAccuracy = appActive ? Self.maxAccuracyMeters : Self.maxBackgroundAccuracyMeters
        guard Self.isAcceptedAccuracy(location.horizontalAccuracy, max: maxAccuracy) else {
            NSLog("[LocationTracker] Punto descartado accuracy=\(location.horizontalAccuracy)m appActive=\(appActive)")
            return
        }

        guard Self.isWithinSchedule() else {
            NSLog("[LocationTracker] Fuera de horario, deteniendo tracker")
            stop()
            return
        }

        let point = Self.makePoint(from: location)

        maybeAlertArrival(at: location)
        deliver(point)
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Reanuda tracking automáticamente al obtener Always y mantiene compatibilidad con iOS 13+][obj: LocationTracker.locationManagerDidChangeAuthorization]
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = locationManager.currentAuthorizationStatus()
        switch Self.authorizationTransition(
            authorizationStatus: status,
            shouldStartWhenAuthorized: shouldStartWhenAuthorized,
            isTracking: isTracking
        ) {
        case .startTracking:
            shouldStartWhenAuthorized = false
            isTracking = true
            locationManager.startUpdatingLocation()
            NSLog("[LocationTracker] TRACKING_IOS_START autorizado")
        case .keepWaitingForAlways:
            NSLog("[LocationTracker] Se requiere permiso Always para tracking en background")
        case .stopTracking:
            shouldStartWhenAuthorized = false
            stop()
        case .refreshTracking:
            locationManager.startUpdatingLocation()
        case .noOp:
            return
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[LocationTracker] Error: \(error.localizedDescription)")
    }

    // MARK: - Privado

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 13:40 UTC-5 (Lima)][desc: En background nativo siempre encola primero; solo entrega al EventChannel cuando la app está realmente activa para evitar perder puntos con sink vivo pero engine suspendido][obj: LocationTracker.deliver background queue]
    private func deliver(_ point: [String: Any]) {
        eventBridge.dispatchQueuedOrLivePoint(
            point,
            isFlutterActive: isFlutterActive,
            appIsActive: Self.isApplicationActive(),
            enqueueFallback: enqueue
        )
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Escribe directo a SQLite en background para que BGAppRefreshTask pueda flushar sin necesitar el engine Flutter. Usa tracking_uid (persiste tras logout) no auth_uid (se borra en logout), igual que LocationTrackingService.kt en Android][obj: LocationTracker.enqueue sqlite]
    private func enqueue(_ point: [String: Any]) {
        let uid = Self.resolveTrackingUid()
        guard !uid.isEmpty else {
            NSLog("[LocationTracker] ENQUEUE_IOS_SKIP sin tracking_uid")
            return
        }
        PendingFlushService.insertLocation(uid: uid, point: point)
        let count = PendingFlushService.countPending(uid: uid)
        if count >= 10 {
            NSLog("[LocationTracker] BATCH_FLUSH_TRIGGERED count=\(count)")
            DispatchQueue.global(qos: .background).async {
                PendingFlushService.flush()
            }
        }
    }

    private func maybeAlertArrival(at location: CLLocation) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "flutter.arrival_target_enabled") else { return }
        guard let latStr = defaults.string(forKey: "flutter.arrival_target_lat"),
              let lngStr = defaults.string(forKey: "flutter.arrival_target_lng"),
              let radiusStr = defaults.string(forKey: "flutter.arrival_target_radius_m"),
              let lat = Double(latStr),
              let lng = Double(lngStr),
              let radius = Double(radiusStr) else { return }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let lastMs = defaults.double(forKey: "flutter.arrival_last_alert_ms")
        guard nowMs - lastMs >= 120_000 else { return }

        let target = CLLocation(latitude: lat, longitude: lng)
        let distance = location.distance(from: target)
        guard distance <= radius else { return }

        defaults.set(nowMs, forKey: "flutter.arrival_last_alert_ms")
        NSLog("[LocationTracker] Arrival alert triggered. distance=\(distance) radius=\(radius)")
        showArrivalNotification()
    }

    private func showArrivalNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                NSLog("[LocationTracker] Notificaciones no autorizadas")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Llegaste a tu destino"
            content.body = "Ingresa a la app confirmar tu llegada"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "arrival_\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error = error {
                    NSLog("[LocationTracker] Notification error: \(error.localizedDescription)")
                }
            }
        }
    }

    static func isAcceptedAccuracy(_ accuracy: Double, max: Double = maxAccuracyMeters) -> Bool {
        accuracy >= 0 && accuracy <= max
    }

    static func isWithinSchedule(
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        BackgroundScheduleChannel.shouldTrack(at: date, defaults: defaults)
    }

    static func makePoint(
        from location: CLLocation,
        timeZone: TimeZone = TimeZone(identifier: "America/Lima") ?? .current
    ) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone

        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "timestamp": formatter.string(from: location.timestamp),
            "accuracy": location.horizontalAccuracy,
            "altitude": location.altitude,
            "speed": max(location.speed, 0),
            "heading": location.course >= 0 ? location.course : 0.0,
            "source": "native_ios",
        ]
    }

    static func shouldDeliverToSink(
        isFlutterActive: Bool,
        appIsActive: Bool,
        hasEventSink: Bool
    ) -> Bool {
        !isFlutterActive && appIsActive && hasEventSink
    }

    static func resolveTrackingUid(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: "flutter.tracking_uid") ?? ""
    }

    static func isApplicationActive() -> Bool {
        if Thread.isMainThread {
            return UIApplication.shared.applicationState == .active
        }
        return DispatchQueue.main.sync {
            UIApplication.shared.applicationState == .active
        }
    }

    static func startAction(
        authorizationStatus: CLAuthorizationStatus,
        isFlutterActive: Bool
    ) -> StartAction {
        guard !isFlutterActive else { return .noOp }

        switch authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            return .requestAlwaysAuthorization
        case .authorizedAlways:
            return .startUpdatingLocation
        case .denied, .restricted:
            return .deny
        @unknown default:
            return .deny
        }
    }

    static func authorizationTransition(
        authorizationStatus: CLAuthorizationStatus,
        shouldStartWhenAuthorized: Bool,
        isTracking: Bool
    ) -> AuthorizationTransition {
        if shouldStartWhenAuthorized && authorizationStatus == .authorizedAlways {
            return .startTracking
        }
        if shouldStartWhenAuthorized && authorizationStatus == .authorizedWhenInUse {
            return .keepWaitingForAlways
        }
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            return .stopTracking
        }
        if isTracking && authorizationStatus == .authorizedAlways {
            return .refreshTracking
        }
        return .noOp
    }

    static func dispatchPoint(
        point: [String: Any],
        isFlutterActive: Bool,
        appIsActive: Bool,
        eventSink: FlutterEventSink?,
        enqueuePoint: @escaping ([String: Any]) -> Void
    ) {
        LocationPointDispatcher(
            isFlutterActive: isFlutterActive,
            appIsActiveProvider: { appIsActive },
            enqueuePoint: enqueuePoint
        ).dispatch(point: point, eventSink: eventSink)
    }
}
