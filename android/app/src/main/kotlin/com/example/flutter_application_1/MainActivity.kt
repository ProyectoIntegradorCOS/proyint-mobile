package com.example.flutter_application_1

import com.example.flutter_application_1.schedule.AlarmScheduler
import com.example.flutter_application_1.schedule.SchedulePrefs
import com.example.flutter_application_1.schedule.TrackingWindowEnforcer
import com.example.flutter_application_1.tracking.PendingLocationApiClient
import com.example.flutter_application_1.tracking.TrackingDb
import com.example.flutter_application_1.navigation.NavigationActivity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.flutter_application_1.telemetry.TelemetryFileLogger
import com.example.flutter_application_1.tracking.LocationTrackingService
import com.example.flutter_application_1.security.SecurePrefs

class MainActivity : FlutterActivity() {
  private var screenStateChannel: MethodChannel? = null
  private var arrivalRingtone: Ringtone? = null
  private var screenReceiverRegistered = false
  private val screenStateReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      val action = intent?.action ?: return
      when (action) {
        Intent.ACTION_SCREEN_OFF -> {
          showScreenStateNotification("APP con pantalla apagada")
          recordScreenEvent("screen_off")
          notifyFlutterScreenState("screen_off")
        }
        Intent.ACTION_SCREEN_ON -> {
          showScreenStateNotification("Pantalla encendida")
          recordScreenEvent("screen_on")
          notifyFlutterScreenState("screen_on")
        }
      }
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    SchedulePrefs.setAppInForeground(applicationContext, true)
    TelemetryFileLogger.log(
      applicationContext,
      "MainActivity.onCreate action=${intent?.action} fromArrival=${intent?.getBooleanExtra("from_arrival_notification", false)} flags=${intent?.flags}",
    )
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    TelemetryFileLogger.log(
      applicationContext,
      "MainActivity.onNewIntent action=${intent.action} fromArrival=${intent.getBooleanExtra("from_arrival_notification", false)} flags=${intent.flags}",
    )
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Exponer MethodChannel para programar/cancelar AlarmManager exacto desde Flutter][obj: MainActivity.configureFlutterEngine]
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "pe.gob.onp.thaqhiri/background_schedule",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "scheduleAlarms" -> {
          AlarmScheduler.scheduleAll(applicationContext)
          result.success(true)
        }
        "cancelAlarms" -> {
          AlarmScheduler.cancelAll(applicationContext)
          result.success(true)
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Permite forzar enforce del window de tracking inmediatamente (útil tras logout dentro de horario)][obj: MainActivity.enforceNow]
        "enforceNow" -> {
          TrackingWindowEnforcer.enforce(applicationContext)
          result.success(true)
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Permite informar a Android si el tracking foreground de Flutter está activo, para evitar doble encolado][obj: MainActivity.setForegroundTrackingActive]
        "setForegroundTrackingActive" -> {
          val active = call.argument<Boolean>("active") ?: false
          SchedulePrefs.setForegroundTrackingActive(applicationContext, active)
          TrackingWindowEnforcer.enforce(applicationContext)
          result.success(true)
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:45 UTC-5 (Lima)][desc: Programa/cancela flush de ubicaciones pendientes en background vía AlarmManager][obj: MainActivity.pendingFlush]
        "schedulePendingFlush" -> {
          AlarmScheduler.schedulePendingFlush(applicationContext)
          result.success(true)
        }
        "cancelPendingFlush" -> {
          AlarmScheduler.cancelPendingFlush(applicationContext)
          result.success(true)
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 UTC-5 (Lima)][desc: Inicia/detiene tracking nativo continuo (foreground service)][obj: MainActivity.native_tracking]
        "startNativeTracking" -> {
          val trackingUid = SchedulePrefs.getTrackingUid(applicationContext)
          if (trackingUid.isNullOrBlank()) {
            result.error("no_uid", "No hay tracking_uid en SharedPreferences", null)
            return@setMethodCallHandler
          }
          if (!hasLocationPermissions(applicationContext) || !hasForegroundLocationPermission(applicationContext)) {
            result.error("no_permission", "Permisos de ubicación insuficientes para iniciar tracking nativo", null)
            return@setMethodCallHandler
          }
          val i = Intent(applicationContext, LocationTrackingService::class.java)
          i.putExtra("tracking_uid", trackingUid)
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(i)
          } else {
            applicationContext.startService(i)
          }
          result.success(true)
        }
        "stopNativeTracking" -> {
          applicationContext.stopService(Intent(applicationContext, LocationTrackingService::class.java))
          result.success(true)
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Flush inmediato del SQLite nativo al backend cuando el usuario abre la app o hace login][obj: MainActivity.flushNativePendingNow]
        "flushNativePendingNow" -> {
          val apiBase = SchedulePrefs.getApiBaseUrl(applicationContext)
          val token = SchedulePrefs.getAuthToken(applicationContext)
          val uid = SchedulePrefs.getAuthUid(applicationContext) ?: SchedulePrefs.getTrackingUid(applicationContext)
          if (apiBase == null || token == null || uid == null) {
            result.success("skip:missing_credentials")
            return@setMethodCallHandler
          }
          Thread {
            try {
              var totalSent = 0
              while (true) {
                val batch = TrackingDb.getPendingBatch(applicationContext, uid, 10)
                if (batch.isEmpty()) break
                val ok = PendingLocationApiClient.sendBatch(apiBase, token, batch)
                if (ok) {
                  TrackingDb.deletePendingByIds(applicationContext, batch.map { it.id })
                  totalSent += batch.size
                } else break
              }
              val remaining = TrackingDb.countPendingForSubject(applicationContext, uid)
              SchedulePrefs.setNativeLastPoint(applicationContext,
                SchedulePrefs.getNativeLastLat(applicationContext) ?: 0.0,
                SchedulePrefs.getNativeLastLng(applicationContext) ?: 0.0,
                remaining)
              result.success("ok:sent=$totalSent remaining=$remaining")
            } catch (e: Exception) {
              result.error("flush_error", e.message, null)
            }
          }.start()
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Devuelve conteo de puntos pendientes en SQLite nativo para diagnóstico][obj: MainActivity.getNativeSqliteCount]
        "getNativeSqliteCount" -> {
          val uid = SchedulePrefs.getAuthUid(applicationContext) ?: SchedulePrefs.getTrackingUid(applicationContext)
          if (uid == null) {
            result.success(0)
          } else {
            result.success(TrackingDb.countPendingForSubject(applicationContext, uid))
          }
        }
        else -> result.notImplemented()
      }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-27 UTC-5 (Lima)][desc: Canal para sincronizar token seguro hacia EncryptedSharedPreferences][obj: MainActivity.secure_store channel]
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "pe.gob.onp.thaqhiri/secure_store",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "setToken" -> {
          val token = call.argument<String>("token")
          if (token.isNullOrBlank()) {
            result.error("invalid_args", "token vacío", null)
            return@setMethodCallHandler
          }
          SecurePrefs.setAuthToken(applicationContext, token)
          result.success(true)
        }
        "clearToken" -> {
          SecurePrefs.clearAuthToken(applicationContext)
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Exponer MethodChannel para abrir navegación nativa Mapbox (Android)][obj: MainActivity.navigation channel]
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "pe.gob.onp.thaqhiri/navigation",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "startNavigation" -> {
          val accessToken = call.argument<String>("accessToken") ?: ""
          val profile = call.argument<String>("profile") ?: "walking"
          @Suppress("UNCHECKED_CAST")
          val waypoints =
            call.argument<List<HashMap<String, Double>>>("waypoints") ?: emptyList()

          if (accessToken.isBlank() || waypoints.size < 2) {
            result.error("invalid_args", "accessToken/waypoints inválidos", null)
            return@setMethodCallHandler
          }

          val intent = NavigationActivity.buildIntent(
            this,
            accessToken,
            profile,
            ArrayList(waypoints),
          )
          startActivity(intent)
          result.success(true)
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Permite actualizar ruta en caliente enviando broadcast a NavigationActivity (si está abierta)][obj: MainActivity.updateNavigationRoute]
        "updateRoute" -> {
          val profile = call.argument<String>("profile") ?: "walking"
          @Suppress("UNCHECKED_CAST")
          val waypoints =
            call.argument<List<HashMap<String, Double>>>("waypoints") ?: emptyList()
          if (waypoints.size < 2) {
            result.error("invalid_args", "Se requieren >=2 puntos", null)
            return@setMethodCallHandler
          }
          val intent = Intent(NavigationActivity.ACTION_UPDATE_ROUTE).apply {
            setPackage(packageName)
            putExtra(NavigationActivity.EXTRA_PROFILE, profile)
            putExtra(NavigationActivity.EXTRA_WAYPOINTS, ArrayList(waypoints))
          }
          sendBroadcast(intent)
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-23 UTC-5 (Lima)][desc: Alertas nativas de llegada (vibración/sonido) cuando app está en background][obj: MainActivity.arrival_alert]
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "pe.gob.onp.thaqhiri/arrival_alert",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "notify" -> {
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

          result.success(true)
        }
        "cancel" -> {
          try {
            arrivalRingtone?.stop()
            arrivalRingtone = null
          } catch (_: Exception) {}
          try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(4243)
          } catch (_: Exception) {}
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-23 UTC-5 (Lima)][desc: Notificación nativa al cambiar entre tracking nativo/Flutter][obj: MainActivity.tracking_mode_notify]
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "pe.gob.onp.thaqhiri/tracking_mode_notify",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "notify" -> {
          val mode = call.argument<String>("mode") ?: "Flutter"
          try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "tracking_mode_channel"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              val channel = NotificationChannel(
                channelId,
                "Tracking mode",
                NotificationManager.IMPORTANCE_LOW,
              )
              nm.createNotificationChannel(channel)
            }
            val notification = NotificationCompat.Builder(this, channelId)
              .setSmallIcon(R.mipmap.ic_launcher)
              .setContentTitle("Tracking activo")
              .setContentText("Modo: $mode")
              .setAutoCancel(true)
              .build()
            nm.notify(9901, notification)
          } catch (_: Exception) {}
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 UTC-5 (Lima)][desc: Canal para notificar estado de pantalla (on/off) hacia Flutter][obj: MainActivity.screen_state channel]
    screenStateChannel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "pe.gob.onp.thaqhiri/screen_state",
    )
    screenStateChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "getPendingEvents" -> {
          result.success(consumeScreenEvents())
        }
        else -> result.notImplemented()
      }
    }
  }

  override fun onStart() {
    super.onStart()
    SchedulePrefs.setAppInForeground(applicationContext, true)
    TelemetryFileLogger.log(
      applicationContext,
      "MainActivity.onStart action=${intent?.action} fromArrival=${intent?.getBooleanExtra("from_arrival_notification", false)}",
    )
    if (!screenReceiverRegistered) {
      val filter = IntentFilter().apply {
        addAction(Intent.ACTION_SCREEN_OFF)
        addAction(Intent.ACTION_SCREEN_ON)
      }
      registerReceiver(screenStateReceiver, filter)
      screenReceiverRegistered = true
    }
  }

  override fun onStop() {
    SchedulePrefs.setAppInForeground(applicationContext, false)
    if (screenReceiverRegistered) {
      unregisterReceiver(screenStateReceiver)
      screenReceiverRegistered = false
    }
    super.onStop()
  }

  private fun notifyFlutterScreenState(state: String) {
    try {
      screenStateChannel?.invokeMethod(state, null)
    } catch (_: Exception) {}
  }

  private fun recordScreenEvent(event: String) {
    try {
      val prefs = getSharedPreferences("thaqhiri_prefs", MODE_PRIVATE)
      val existing = prefs.getString("screen_events", "") ?: ""
      val entry = "$event|${System.currentTimeMillis()}"
      val updated = if (existing.isBlank()) entry else "$existing\n$entry"
      prefs.edit().putString("screen_events", updated).apply()
    } catch (_: Exception) {}
  }

  private fun consumeScreenEvents(): List<String> {
    return try {
      val prefs = getSharedPreferences("thaqhiri_prefs", MODE_PRIVATE)
      val raw = prefs.getString("screen_events", "") ?: ""
      prefs.edit().remove("screen_events").apply()
      raw.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
    } catch (_: Exception) {
      emptyList()
    }
  }

  private fun showScreenStateNotification(message: String) {
    try {
      val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
      val channelId = "screen_state_channel"
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channel = NotificationChannel(
          channelId,
          "Screen state",
          NotificationManager.IMPORTANCE_LOW,
        )
        nm.createNotificationChannel(channel)
      }
      val notification = NotificationCompat.Builder(this, channelId)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle("Estado de pantalla")
        .setContentText(message)
        .setAutoCancel(true)
        .build()
      nm.notify(9902, notification)
    } catch (_: Exception) {}
  }

  private fun hasLocationPermissions(context: Context): Boolean {
    val fine = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED
    val coarse = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED
    return fine || coarse
  }

  private fun hasForegroundLocationPermission(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < 34) return true
    return ContextCompat.checkSelfPermission(
      context,
      android.Manifest.permission.FOREGROUND_SERVICE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
  }
}
