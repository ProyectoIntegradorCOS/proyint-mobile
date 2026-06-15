// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Servicio nativo foreground para tracking de ubicación y encolado en SQLite incluso con app cerrada][obj: LocationTrackingService]
package com.example.flutter_application_1.tracking

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.flutter_application_1.R
import com.example.flutter_application_1.schedule.AlarmActions
import com.example.flutter_application_1.schedule.SchedulePrefs
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import android.location.Location
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.flutter_application_1.telemetry.TelemetryFileLogger
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class LocationTrackingService : Service() {
    companion object {
        private const val CHANNEL_ID = "location_tracking_channel"
        private const val NOTIFICATION_ID = 4242
        private const val TAG = "LocationTrackingService"
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 10:13 UTC-5 (Lima)][desc: Umbral de precisión para descartar puntos ruidosos en background][obj: LocationTrackingService accuracy filter]
        private const val MAX_ACCURACY_METERS = 50.0f
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-23 UTC-5 (Lima)][desc: Intervalo mínimo entre alertas de llegada para evitar spam][obj: LocationTrackingService arrival alert throttle]
        private const val MIN_ARRIVAL_ALERT_MS = 120_000L
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Número máximo de alertas por destino antes de auto-desactivar][obj: LocationTrackingService arrival alert max]
        private const val MAX_ARRIVAL_ALERTS = 2
        private const val BATCH_FLUSH_THRESHOLD = 10
        private const val ARRIVAL_CHANNEL_ID = "arrival_alerts_channel"
        private const val ARRIVAL_NOTIFICATION_ID = 4243
    }

    private val fused by lazy { LocationServices.getFusedLocationProviderClient(this) }
    private var callback: LocationCallback? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var arrivalRingtone: Ringtone? = null

    override fun onCreate() {
        super.onCreate()
        if (!hasLocationPermissions() || !hasForegroundLocationPermission()) {
            Log.w(TAG, "onCreate: permisos insuficientes para iniciar FGS, deteniendo servicio")
            stopSelf()
            return
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 16:30 UTC-5 (Lima)][desc: Adquiere WakeLock para asegurar que el CPU no duerma durante el tracking nativo][obj: LocationTrackingService.onCreate wakeLock]
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Thaqhiri:TrackingWakeLock")
        wakeLock?.acquire()

        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Log inicial del servicio nativo para trazar encolado incluso sin sesión][obj: LocationTrackingService.onCreate log]
        Log.i(TAG, "onCreate: servicio iniciado (foreground)")
        startForeground(NOTIFICATION_ID, buildNotification())
        startLocationUpdates()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!hasLocationPermissions() || !hasForegroundLocationPermission()) {
            Log.w(TAG, "onStartCommand: permisos insuficientes para iniciar FGS, deteniendo servicio")
            stopSelf()
            return START_NOT_STICKY
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Permite recibir tracking_uid desde AlarmReceiver y persistirlo en prefs][obj: LocationTrackingService.onStartCommand]
        val incomingUid = intent?.getStringExtra("tracking_uid")
        if (!incomingUid.isNullOrBlank()) {
            // preferimos el tracking_uid persistente; no se borra con logout real.
            SchedulePrefs.setTrackingUid(this, incomingUid)
            Log.i(TAG, "onStartCommand: tracking_uid actualizado=$incomingUid")
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Reafirma foreground y reinicia updates si callback quedó null (ej. tras ciclos login/logout)][obj: LocationTrackingService.onStartCommand restart updates]
        try {
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {}
        if (callback == null) {
            Log.i(TAG, "onStartCommand: callback null, reiniciando location updates")
            startLocationUpdates()
        } else {
            Log.i(TAG, "onStartCommand: callback activa, location updates ya en curso")
        }
        Log.i(TAG, "TRACKING_NATIVE_START")
        // Mantener servicio activo si el sistema lo reinicia.
        return START_STICKY
    }

    override fun onDestroy() {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Log de destrucción para diagnosticar reinicios/paradas del servicio nativo][obj: LocationTrackingService.onDestroy log]
        Log.i(TAG, "onDestroy: servicio detenido")
        Log.i(TAG, "TRACKING_NATIVE_STOP")
        arrivalRingtone?.stop()
        arrivalRingtone = null
        stopLocationUpdates()
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 16:30 UTC-5 (Lima)][desc: Libera WakeLock al detener el servicio][obj: LocationTrackingService.onDestroy wakeLock]
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Location Tracking",
                NotificationManager.IMPORTANCE_LOW,
            )
            nm.createNotificationChannel(channel)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Sistema activo")
            .setContentText("La app está registrando tu ubicación")
            .setOngoing(true)
            .build()
    }

    private fun startLocationUpdates() {
        val hasFine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) {
            stopSelf()
            return
        }

        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 16:55 UTC-5 (Lima)][desc: Aumenta frecuencia nativa (5s) y elimina delay de batching para máxima granularidad en background][obj: LocationTrackingService startLocationUpdates rate]
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-13 15:45 UTC-5 (Lima)][desc: Tracking crítico continuo (intervalo 2s, distancia 0m)][obj: LocationTrackingService startLocationUpdates critical]
        val prefs = SchedulePrefs.prefs(this)
        val intervalSeconds = prefs.getLong("flutter.tracking_capture_interval_s", 10L).toInt().coerceIn(1, 120)
        val distanceMeters = prefs.getLong("flutter.tracking_capture_distance_m", 10L).toFloat().coerceIn(1f, 100f)

        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalSeconds * 1000L)
            .setMinUpdateIntervalMillis(intervalSeconds * 1000L)
            .setMinUpdateDistanceMeters(distanceMeters)
            .setMaxUpdateDelayMillis(0)
            .build()

        callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                try {
                    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 16:40 UTC-5 (Lima)][desc: Log de diagnóstico para confirmar recepción de ubicación nativa][obj: LocationTrackingService.onLocationResult trace]
                    val loc = result.lastLocation
                    if (loc == null) {
                        Log.d(TAG, "onLocationResult: result.lastLocation es null")
                        return
                    }

                    if (loc.hasAccuracy() && loc.accuracy > MAX_ACCURACY_METERS) {
                        Log.i(TAG, "onLocationResult: descartado por accuracy=${loc.accuracy}")
                        return
                    }

                    val saaSubject = SchedulePrefs.getTrackingUid(this@LocationTrackingService)
                    if (saaSubject == null) {
                        Log.d(TAG, "onLocationResult: trackingUid es null, abortando")
                        return
                    }

                    val schedule = SchedulePrefs.getStoredSchedule(this@LocationTrackingService)
                    if (schedule == null) {
                        Log.d(TAG, "onLocationResult: schedule es null, abortando")
                        return
                    }

                    val now = java.time.LocalDateTime.now(ZoneId.of("America/Lima"))
                    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 18:36 UTC-5 (Lima)][desc: Evita tracking en fines de semana (solo L-V)][obj: LocationTrackingService weekday guard]
                    val isWeekday = now.dayOfWeek.value in 1..5
                    if (!isWeekday) {
                        Log.i(TAG, "onLocationResult: fin de semana, deteniendo. uid=$saaSubject now=$now")
                        stopSelf()
                        return
                    }
                    val start = java.time.LocalDateTime.of(now.toLocalDate(), java.time.LocalTime.of(schedule.startHour, 0))
                    var end = java.time.LocalDateTime.of(now.toLocalDate(), java.time.LocalTime.of(schedule.endHour, 0))
                    if (!end.isAfter(start)) end = end.plusDays(1)

                    if (now.isBefore(start) || !now.isBefore(end)) {
                        Log.i(TAG, "onLocationResult: fuera de horario, deteniendo. uid=$saaSubject now=$now window=${schedule.startHour}-${schedule.endHour}")
                        stopSelf()
                        return
                    }

                    maybeAlertArrival(loc)
                    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Timestamp se guarda en hora Lima (UTC-5) para consistencia con reportes/BD][obj: LocationTrackingService timestamp Lima]
                    val ts = OffsetDateTime.now(ZoneId.of("America/Lima"))
                        .withNano(0)
                        .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
                    val tsEpoch = System.currentTimeMillis()
                    TrackingDb.insertPendingLocation(
                        context = this@LocationTrackingService,
                        saaSubject = saaSubject,
                        latitude = loc.latitude,
                        longitude = loc.longitude,
                        timestampIso = ts,
                        timestampEpochMs = tsEpoch,
                        accuracy = loc.accuracy.toDouble(),
                        altitude = if (loc.hasAltitude()) loc.altitude else 0.0,
                        speed = if (loc.hasSpeed()) loc.speed.toDouble() else 0.0,
                        heading = if (loc.hasBearing()) loc.bearing.toDouble() else 0.0,
                        batteryLevel = 0.0,
                        activityType = "unknown",
                    )
                    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Log de encolado para trazar capturas aun cuando el usuario esté deslogueado][obj: LocationTrackingService enqueue log]
                    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Incluye tokenPresent para distinguir encolado con/sin sesión][obj: LocationTrackingService enqueue tokenPresent]
                    val tokenPresent = !SchedulePrefs.getAuthToken(this@LocationTrackingService).isNullOrBlank()
                    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Guarda último punto y conteo en SharedPreferences para telemetría Flutter][obj: LocationTrackingService setNativeLastPoint]
                    val sqliteCount = TrackingDb.countPendingForSubject(this@LocationTrackingService, saaSubject)
                    SchedulePrefs.setNativeLastPoint(this@LocationTrackingService, loc.latitude, loc.longitude, sqliteCount)
                    if (sqliteCount >= BATCH_FLUSH_THRESHOLD) {
                        val flushIntent = Intent(this@LocationTrackingService, com.example.flutter_application_1.schedule.ScheduleAlarmReceiver::class.java)
                        flushIntent.action = AlarmActions.ACTION_FLUSH_PENDING
                        sendBroadcast(flushIntent)
                        Log.i(TAG, "BATCH_FLUSH_TRIGGERED count=$sqliteCount")
                    }
                    Log.i(
                        TAG,
                        "ENQUEUE_OK uid=$saaSubject tokenPresent=$tokenPresent lat=${loc.latitude} lng=${loc.longitude} ts=$ts sqlitePendientes=$sqliteCount",
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "onLocationResult failed", e)
                    TelemetryFileLogger.log(
                        this@LocationTrackingService,
                        "onLocationResult failed: ${e::class.java.simpleName}: ${e.message}",
                    )
                }
            }
        }
        fused.requestLocationUpdates(request, callback!!, mainLooper)
    }

    private fun stopLocationUpdates() {
        val cb = callback ?: return
        fused.removeLocationUpdates(cb)
        callback = null
    }

    private fun hasLocationPermissions(): Boolean {
        val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun hasForegroundLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.FOREGROUND_SERVICE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun maybeAlertArrival(loc: android.location.Location) {
        if (!SchedulePrefs.isArrivalTargetEnabled(this)) return
        val lat = SchedulePrefs.getArrivalTargetLat(this) ?: return
        val lng = SchedulePrefs.getArrivalTargetLng(this) ?: return
        val radius = SchedulePrefs.getArrivalTargetRadius(this) ?: return

        val now = System.currentTimeMillis()
        val last = SchedulePrefs.getArrivalLastAlertAt(this)
        if (now - last < MIN_ARRIVAL_ALERT_MS) return

        val results = FloatArray(1)
        Location.distanceBetween(
            loc.latitude, loc.longitude,
            lat, lng,
            results
        )
        val distance = results[0].toDouble()
        if (distance > radius) return
        TelemetryFileLogger.log(
            this,
            "Arrival alert candidate: lat=${loc.latitude}, lng=${loc.longitude}, distance=$distance, radius=$radius",
        )

        // Dispara alerta nativa
        try {
            val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(400, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(400)
            }
        } catch (_: Exception) {}

        try {
            arrivalRingtone?.stop()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            arrivalRingtone = RingtoneManager.getRingtone(applicationContext, uri)
            arrivalRingtone?.play()
            Handler(Looper.getMainLooper()).postDelayed({
                arrivalRingtone?.stop()
                arrivalRingtone = null
            }, 5_000L)
        } catch (_: Exception) {}

        showArrivalNotification()
        TelemetryFileLogger.log(
            this,
            "Arrival alert notification dispatched: distance=$distance radius=$radius",
        )
        SchedulePrefs.setArrivalLastAlertAt(this, now)
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Incrementa contador; al llegar a MAX_ARRIVAL_ALERTS deshabilita el target para no repetir indefinidamente][obj: LocationTrackingService.maybeAlertArrival max alerts]
        val alertCount = SchedulePrefs.incrementArrivalAlertCount(this)
        if (alertCount >= MAX_ARRIVAL_ALERTS) {
            SchedulePrefs.disableArrivalTarget(this)
            Log.i(TAG, "Arrival alert disabled after $alertCount alerts. distance=$distance radius=$radius")
        } else {
            Log.i(TAG, "Arrival alert triggered ($alertCount/$MAX_ARRIVAL_ALERTS). distance=$distance radius=$radius")
        }
    }

    private fun showArrivalNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    ARRIVAL_CHANNEL_ID,
                    "Alertas de llegada",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Notificaciones cuando llegas a tu destino de visita"
                    enableVibration(true)
                    enableLights(true)
                }
                nm.createNotificationChannel(channel)
            }
            TelemetryFileLogger.log(this, "showArrivalNotification: channel ready")

            val builder = NotificationCompat.Builder(this, ARRIVAL_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Llegaste a tu destino")
                .setContentText("Ingresa a la app para confirmar")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)

            val appInForeground = SchedulePrefs.isAppInForeground(this)
            TelemetryFileLogger.log(
                this,
                "showArrivalNotification: appInForeground=$appInForeground",
            )
            if (!appInForeground) {
                val launchIntent = Intent(this, com.example.flutter_application_1.MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("from_arrival_notification", true)
                }

                TelemetryFileLogger.log(
                    this,
                    "showArrivalNotification: explicit MainActivity intent prepared flags=${launchIntent.flags}",
                )
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                builder.setContentIntent(pendingIntent)
                TelemetryFileLogger.log(this, "showArrivalNotification: pendingIntent attached")
            } else {
                TelemetryFileLogger.log(
                    this,
                    "showArrivalNotification: skipping contentIntent because app is already foreground",
                )
            }

            nm.notify(ARRIVAL_NOTIFICATION_ID, builder.build())
            TelemetryFileLogger.log(this, "showArrivalNotification: notify OK id=$ARRIVAL_NOTIFICATION_ID")
        } catch (e: Exception) {
            Log.e(TAG, "showArrivalNotification failed", e)
            TelemetryFileLogger.log(
                this,
                "showArrivalNotification failed: ${e::class.java.simpleName}: ${e.message}",
            )
        }
    }
}
