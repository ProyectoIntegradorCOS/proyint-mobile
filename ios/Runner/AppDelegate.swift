// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:51 UTC-5 (Lima)][desc: Registra EventChannel location_stream para que LocationTracker.swift entregue puntos a Flutter][obj: AppDelegate EventChannel location_stream]
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:55 UTC-5 (Lima)][desc: Agrega MethodChannel background_schedule y registro de BGAppRefreshTask pendingFlush][obj: AppDelegate MethodChannel + BGTask]
import BackgroundTasks
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Registra canales iOS usando FlutterPluginRegistry para evitar dependencia de rootViewController en el arranque][obj: AppDelegate.didFinishLaunchingWithOptions registrar]
        GeneratedPluginRegistrant.register(with: self)
        guard let registrar = registrar(forPlugin: "pe.gob.onp.thaqhiri.app_delegate") else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        let messenger = registrar.messenger()

        // EventChannel: LocationTracker.swift → Flutter
        // Dart escucha en LocationService.startNativeListener()
        FlutterEventChannel(
            name: "pe.gob.onp.thaqhiri/location_stream",
            binaryMessenger: messenger
        ).setStreamHandler(LocationStreamHandler())

        // MethodChannel: Flutter → iOS (equivalente al Kotlin BackgroundScheduleManager)
        FlutterMethodChannel(
            name: "pe.gob.onp.thaqhiri/background_schedule",
            binaryMessenger: messenger
        ).setMethodCallHandler { call, result in
            BackgroundScheduleChannel.handle(call: call, result: result)
        }

        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Registra secure_store en iOS para sincronizar auth_token nativo y habilitar flush background sin depender del plugin][obj: AppDelegate secure_store channel]
        FlutterMethodChannel(
            name: "pe.gob.onp.thaqhiri/secure_store",
            binaryMessenger: messenger
        ).setMethodCallHandler { call, result in
            SecureStoreChannel.handle(call: call, result: result)
        }

        // MethodChannel: Flutter → iOS arrival_alert (cancela notificación al confirmar llegada)
        FlutterMethodChannel(
            name: "pe.gob.onp.thaqhiri/arrival_alert",
            binaryMessenger: messenger
        ).setMethodCallHandler { call, result in
            if call.method == "cancel" {
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                result(true)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        // BGAppRefreshTask: flush de ubicaciones pendientes
        // Identificador ya declarado en Info.plist > BGTaskSchedulerPermittedIdentifiers
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "pendingFlush",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            BackgroundScheduleChannel.handlePendingFlushTask(refreshTask)
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:51 UTC-5 (Lima)][desc: StreamHandler que conecta el EventChannel con LocationTracker.shared][obj: LocationStreamHandler]
class LocationStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        LocationTracker.shared.setEventSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        LocationTracker.shared.setEventSink(nil)
        return nil
    }
}
