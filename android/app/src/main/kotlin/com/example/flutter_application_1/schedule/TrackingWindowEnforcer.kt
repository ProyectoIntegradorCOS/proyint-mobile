// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Enforcer reutilizable del window de tracking (zona Lima) para arrancar/detener servicio nativo][obj: TrackingWindowEnforcer]
package com.example.flutter_application_1.schedule

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.example.flutter_application_1.tracking.LocationTrackingService
import java.time.LocalDateTime
import java.time.ZoneId

object TrackingWindowEnforcer {
    private const val TAG = "TrackingWindowEnforcer"

    fun enforce(context: Context) {
        val trackingUid = SchedulePrefs.getTrackingUid(context) ?: run {
            Log.w(TAG, "enforce: ABORTADO - No hay tracking_uid en SharedPreferences")
            return
        }
        val schedule = SchedulePrefs.getStoredSchedule(context) ?: run {
            Log.w(TAG, "enforce: ABORTADO - No hay horario (bg_ keys) guardado para uid=$trackingUid")
            return
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Evita doble tracking: si Flutter foreground tracking está activo, detiene servicio nativo][obj: TrackingWindowEnforcer fg tracking]
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Respeta nativeAlwaysOn: si está activo no se para el nativo aunque Flutter esté en foreground][obj: TrackingWindowEnforcer native_always_on]
        if (SchedulePrefs.isForegroundTrackingActive(context) && !SchedulePrefs.isNativeAlwaysOn(context)) {
            Log.i(TAG, "enforce: fg_tracking_active=true nativeAlwaysOn=false, deteniendo nativo uid=$trackingUid")
            context.stopService(Intent(context, LocationTrackingService::class.java))
            return
        }

        val zone = ZoneId.of("America/Lima")
        val now = LocalDateTime.now(zone)
        val shouldRun = shouldRun(now, schedule)
        Log.i(
            TAG,
            "enforce: uid=$trackingUid now=$now weekday=${now.dayOfWeek.value in 1..5} window=${schedule.startHour}-${schedule.endHour} shouldRun=$shouldRun",
        )
        if (shouldRun) {
            if (!hasLocationPermissions(context) || !hasForegroundLocationPermission(context)) {
                Log.w(TAG, "enforce: permisos insuficientes para FGS, no se inicia tracking nativo uid=$trackingUid")
                return
            }
            val i = Intent(context, LocationTrackingService::class.java)
            i.putExtra("tracking_uid", trackingUid)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        } else {
            context.stopService(Intent(context, LocationTrackingService::class.java))
        }
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

    internal fun shouldRun(now: LocalDateTime, schedule: StoredSchedule): Boolean {
        val start = LocalDateTime.of(now.toLocalDate(), java.time.LocalTime.of(schedule.startHour, 0))
        var end = LocalDateTime.of(now.toLocalDate(), java.time.LocalTime.of(schedule.endHour, 0))
        if (!end.isAfter(start)) end = end.plusDays(1)

        val isWeekday = now.dayOfWeek.value in 1..5
        return isWeekday && !now.isBefore(start) && now.isBefore(end)
    }
}
