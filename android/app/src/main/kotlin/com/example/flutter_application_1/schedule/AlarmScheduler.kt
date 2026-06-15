// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Scheduler exacto basado en AlarmManager para iniciar/detener tracking y refrescar horario][obj: AlarmScheduler]
package com.example.flutter_application_1.schedule

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.time.Duration
import java.time.LocalDateTime
import java.time.ZoneId

object AlarmScheduler {
    private const val TAG = "AlarmScheduler"
    private const val REQ_REFRESH_BEFORE_START = 1001
    private const val REQ_START = 1002
    private const val REQ_REFRESH_BEFORE_END = 1003
    private const val REQ_STOP = 1004
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:45 UTC-5 (Lima)][desc: RequestCode para flush de pendientes en background][obj: AlarmScheduler REQ_FLUSH_PENDING]
    private const val REQ_FLUSH_PENDING = 1010

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Refresh de horario es +5 min desde inicio y -5 min antes del fin (no pre-inicio)][obj: AlarmScheduler refresh offsets]
    private const val REFRESH_AFTER_START_MINUTES: Long = 5
    private const val REFRESH_BEFORE_END_MINUTES: Long = 5

    fun scheduleAll(context: Context) {
        val schedule = SchedulePrefs.getStoredSchedule(context) ?: run {
            // Sin horario persistido: programar un refresh pronto para intentar poblarlo.
            scheduleSingle(
                context,
                action = AlarmActions.ACTION_REFRESH_BEFORE_START,
                requestCode = REQ_REFRESH_BEFORE_START,
                triggerAtMillis = System.currentTimeMillis() + Duration.ofMinutes(1).toMillis(),
            )
            return
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Horario se evalúa en zona America/Lima aunque el device cambie timezone][obj: AlarmScheduler timezone]
        val zone = ZoneId.of("America/Lima")
        val now = LocalDateTime.now(zone)

        val startBase = LocalDateTime.of(now.toLocalDate(), java.time.LocalTime.of(schedule.startHour, 0))
        var endBase = LocalDateTime.of(now.toLocalDate(), java.time.LocalTime.of(schedule.endHour, 0))
        if (!endBase.isAfter(startBase)) {
            endBase = endBase.plusDays(1)
        }

        val startRefresh = startBase.plusMinutes(REFRESH_AFTER_START_MINUTES)
        val endRefresh = endBase.minusMinutes(REFRESH_BEFORE_END_MINUTES)

        scheduleNext(context, AlarmActions.ACTION_REFRESH_BEFORE_START, REQ_REFRESH_BEFORE_START, startRefresh, zone, now)
        scheduleNext(context, AlarmActions.ACTION_START_TRACKING, REQ_START, startBase, zone, now)
        scheduleNext(context, AlarmActions.ACTION_REFRESH_BEFORE_END, REQ_REFRESH_BEFORE_END, endRefresh, zone, now)
        scheduleNext(context, AlarmActions.ACTION_STOP_TRACKING, REQ_STOP, endBase, zone, now)
    }

    fun cancelAll(context: Context) {
        cancel(context, AlarmActions.ACTION_REFRESH_BEFORE_START, REQ_REFRESH_BEFORE_START)
        cancel(context, AlarmActions.ACTION_START_TRACKING, REQ_START)
        cancel(context, AlarmActions.ACTION_REFRESH_BEFORE_END, REQ_REFRESH_BEFORE_END)
        cancel(context, AlarmActions.ACTION_STOP_TRACKING, REQ_STOP)
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:40 UTC-5 (Lima)][desc: Programa un flush exacto en background (3 min) para enviar ubicaciones pendientes][obj: AlarmScheduler.schedulePendingFlush]
    fun schedulePendingFlush(context: Context, delayMinutes: Long = 2) {
        val triggerAtMillis = System.currentTimeMillis() + Duration.ofMinutes(delayMinutes).toMillis()
        scheduleSingle(context, AlarmActions.ACTION_FLUSH_PENDING, REQ_FLUSH_PENDING, triggerAtMillis)
    }

    fun cancelPendingFlush(context: Context) {
        cancel(context, AlarmActions.ACTION_FLUSH_PENDING, REQ_FLUSH_PENDING)
    }

    private fun scheduleNext(
        context: Context,
        action: String,
        requestCode: Int,
        baseTime: LocalDateTime,
        zone: ZoneId,
        now: LocalDateTime,
    ) {
        var t = baseTime
        if (!t.isAfter(now)) {
            t = t.plusDays(1)
        }
        val triggerAtMillis = t.atZone(zone).toInstant().toEpochMilli()
        scheduleSingle(context, action, requestCode, triggerAtMillis)
    }

    private fun scheduleSingle(
        context: Context,
        action: String,
        requestCode: Int,
        triggerAtMillis: Long,
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        /*if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!alarmManager.canScheduleExactAlarms()) {
                Log.w(TAG, "Exact alarm not allowed; skip scheduling action=$action requestCode=$requestCode")
                return
            }
        }*/

        val intent = Intent(context, ScheduleAlarmReceiver::class.java).setAction(action)
        val pi = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: En Android 12+ sin permiso SCHEDULE_EXACT_ALARM cae a alarma inexacta para que el flush sí se dispare][obj: AlarmScheduler.scheduleSingle exact alarm fallback]
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            Log.w(TAG, "Exact alarm not allowed; using inexact fallback action=$action requestCode=$requestCode")
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        }
    }

    private fun cancel(context: Context, action: String, requestCode: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, ScheduleAlarmReceiver::class.java).setAction(action)
        val pi = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pi)
    }
}
