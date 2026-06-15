// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:55 UTC-5 (Lima)][desc: Implementación iOS del MethodChannel pe.gob.onp.thaqhiri/background_schedule. Espejo de BackgroundScheduleManager.dart / schedule Kotlin][obj: BackgroundScheduleChannel]
import BackgroundTasks
import Flutter
import Foundation

enum BackgroundScheduleChannel {
    static func shouldTrack(
        at date: Date,
        defaults: UserDefaults = .standard,
        timeZone: TimeZone = TimeZone(identifier: "America/Lima") ?? .current
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekday = calendar.component(.weekday, from: date)
        let isWeekday = weekday >= 2 && weekday <= 6

        let startHour = {
            let v = defaults.integer(forKey: "flutter.bg_hora_inicio")
            return v > 0 ? v : 8
        }()
        let endHour = {
            let v = defaults.integer(forKey: "flutter.bg_hora_fin")
            return v > 0 ? v : 20
        }()
        let hour = calendar.component(.hour, from: date)
        return isWeekday && hour >= startHour && hour < endHour
    }

    // MARK: - MethodChannel handler

    static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        // Equivalente a scheduleAll() en AlarmScheduler.kt
        // En iOS no hay alarmas exactas; el tracker ya lee el horario desde UserDefaults.
        // Solo nos aseguramos de que el tracker esté configurado y corriendo si corresponde.
        case "scheduleAlarms":
            enforceSchedule()
            result(nil)

        // Equivalente a cancelAll() en AlarmScheduler.kt
        case "cancelAlarms":
            LocationTracker.shared.stop()
            result(nil)

        // Fuerza evaluación inmediata del horario (inicio/fin)
        case "enforceNow":
            enforceSchedule()
            result(nil)

        // Flutter informa si su propio tracker (geolocator) está activo.
        // Si está activo, detenemos LocationTracker.swift para evitar duplicados.
        case "setForegroundTrackingActive":
            let args = call.arguments as? [String: Any]
            let active = args?["active"] as? Bool ?? false
            LocationTracker.shared.setFlutterActive(active)
            if active {
                LocationTracker.shared.stop()
            } else {
                enforceSchedule()
            }
            result(nil)

        // Inicia el tracker nativo iOS directamente
        case "startNativeTracking":
            LocationTracker.shared.start()
            result(nil)

        // Detiene el tracker nativo iOS directamente
        case "stopNativeTracking":
            LocationTracker.shared.stop()
            result(nil)

        // Programa un BGAppRefreshTask para flush de ubicaciones pendientes
        case "schedulePendingFlush":
            schedulePendingFlushTask()
            result(nil)

        // Cancela el BGAppRefreshTask pendiente
        case "cancelPendingFlush":
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "pendingFlush")
            result(nil)

        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: Flush inmediato del SQLite nativo al backend, llamado desde Flutter al hacer login. Espejo de flushNativePendingNow en Android.][obj: BackgroundScheduleChannel.flushNativePendingNow]
        case "flushNativePendingNow":
            DispatchQueue.global(qos: .utility).async {
                PendingFlushService.flush()
                result("ok")
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - BGAppRefreshTask handler

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:58 UTC-5 (Lima)][desc: BGTask ejecuta PendingFlushService para enviar ubicaciones pendientes sin depender del engine Flutter][obj: BackgroundScheduleChannel.handlePendingFlushTask]
    static func handlePendingFlushTask(_ task: BGAppRefreshTask) {
        NSLog("[BackgroundScheduleChannel] pendingFlush BGTask ejecutado")

        // Reprogramar para la próxima oportunidad antes de empezar
        schedulePendingFlushTask()

        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Evita completar dos veces el BGTask cuando coinciden expirationHandler y flush async][obj: BackgroundScheduleChannel.handlePendingFlushTask completion guard]
        let lock = NSLock()
        var hasCompleted = false
        func complete(_ success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !hasCompleted else { return }
            hasCompleted = true
            task.setTaskCompleted(success: success)
        }

        // Si el sistema corta el tiempo, completar limpiamente
        task.expirationHandler = {
            NSLog("[BackgroundScheduleChannel] pendingFlush BGTask expirado")
            complete(false)
        }

        // Flush en hilo de background para no bloquear el main thread
        DispatchQueue.global(qos: .utility).async {
            PendingFlushService.flush()
            complete(true)
        }
    }

    // MARK: - Privado

    // Evalúa el horario actual y arranca/detiene LocationTracker según corresponda.
    // Replica la lógica de TrackingWindowEnforcer en Android.
    private static func enforceSchedule() {
        if shouldTrack(at: Date()) {
            NSLog("[BackgroundScheduleChannel] enforceSchedule → dentro de horario, iniciando tracker")
            LocationTracker.shared.start()
        } else {
            NSLog("[BackgroundScheduleChannel] enforceSchedule → fuera de horario, deteniendo tracker")
            LocationTracker.shared.stop()
        }
    }

    private static func schedulePendingFlushTask() {
        let request = BGAppRefreshTaskRequest(identifier: "pendingFlush")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60) // mínimo 2 min
        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[BackgroundScheduleChannel] pendingFlush BGTask programado")
        } catch {
            NSLog("[BackgroundScheduleChannel] Error programando BGTask: \(error)")
        }
    }
}
