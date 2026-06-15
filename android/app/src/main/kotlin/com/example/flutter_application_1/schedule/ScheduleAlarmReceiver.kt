// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Receiver de AlarmManager para refrescar horario y arrancar/detener tracking nativo][obj: ScheduleAlarmReceiver]
package com.example.flutter_application_1.schedule

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.flutter_application_1.tracking.PendingLocationApiClient
import com.example.flutter_application_1.tracking.TrackingDb
import java.time.LocalDateTime
import java.time.ZoneId

class ScheduleAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ScheduleAlarmReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == AlarmActions.ACTION_FLUSH_PENDING) {
            handleFlushPending(context)
            return
        }

        when (action) {
            AlarmActions.ACTION_REFRESH_BEFORE_START,
            AlarmActions.ACTION_REFRESH_BEFORE_END,
            -> {
                refreshSchedule(context)
                AlarmScheduler.scheduleAll(context)
                TrackingWindowEnforcer.enforce(context)
            }

            AlarmActions.ACTION_START_TRACKING -> {
                TrackingWindowEnforcer.enforce(context)
                AlarmScheduler.scheduleAll(context)
            }

            AlarmActions.ACTION_STOP_TRACKING -> {
                TrackingWindowEnforcer.enforce(context)
                // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Purga diaria en STOP_TRACKING para aplicar retención incluso con app cerrada][obj: ScheduleAlarmReceiver STOP purge]
                val trackingUid = SchedulePrefs.getTrackingUid(context)
                if (!trackingUid.isNullOrBlank()) {
                    try {
                        com.example.flutter_application_1.tracking.TrackingDb.purgePendingLocations(context, trackingUid)
                    } catch (_: Exception) {}
                }
                AlarmScheduler.scheduleAll(context)
            }
        }
    }

    private fun refreshSchedule(context: Context) {
        val apiBase = SchedulePrefs.getApiBaseUrl(context) ?: return
        val token = SchedulePrefs.getAuthToken(context) ?: return
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Refresh requiere token; uid se toma de auth_uid y cae a tracking_uid si aplica][obj: ScheduleAlarmReceiver.refreshSchedule uid]
        val uid = SchedulePrefs.getAuthUid(context) ?: SchedulePrefs.getTrackingUid(context) ?: return

        val schedule = ScheduleApiClient.fetchScheduleFromBackend(apiBase, uid, token) ?: return
        SchedulePrefs.storeSchedule(context, schedule)
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:45 UTC-5 (Lima)][desc: Flush de ubicaciones pendientes en background vía AlarmManager][obj: ScheduleAlarmReceiver.handleFlushPending]
    private fun handleFlushPending(context: Context) {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Telemetría diagnóstica: escribe estado en cada early return para saber si la alarma disparó][obj: ScheduleAlarmReceiver.handleFlushPending diagnostics]
        val zone = ZoneId.of("America/Lima")
        val now = LocalDateTime.now(zone)
        SchedulePrefs.setLastPendingFlush(context, now.toString(), "invoked")
        if (SchedulePrefs.isForegroundTrackingActive(context)) {
            SchedulePrefs.setLastPendingFlush(context, now.toString(), "skip:fg_active")
            AlarmScheduler.cancelPendingFlush(context)
            return
        }
        val schedule = SchedulePrefs.getStoredSchedule(context) ?: run {
            SchedulePrefs.setLastPendingFlush(context, now.toString(), "skip:no_schedule")
            return
        }
        val start = LocalDateTime.of(now.toLocalDate(), java.time.LocalTime.of(schedule.startHour, 0))
        var end = LocalDateTime.of(now.toLocalDate(), java.time.LocalTime.of(schedule.endHour, 0))
        if (!end.isAfter(start)) end = end.plusDays(1)
        val isWeekday = now.dayOfWeek.value in 1..5
        val shouldRun = isWeekday && !now.isBefore(start) && now.isBefore(end)
        if (!shouldRun) {
            SchedulePrefs.setLastPendingFlush(context, now.toString(), "skip:out_of_schedule day=${now.dayOfWeek} h=${now.hour}")
            AlarmScheduler.cancelPendingFlush(context)
            return
        }

        val apiBase = SchedulePrefs.getApiBaseUrl(context) ?: run {
            SchedulePrefs.setLastPendingFlush(context, now.toString(), "skip:no_api_base")
            return
        }
        val token = SchedulePrefs.getAuthToken(context) ?: run {
            SchedulePrefs.setLastPendingFlush(context, now.toString(), "skip:no_token")
            return
        }
        val uid = SchedulePrefs.getAuthUid(context) ?: SchedulePrefs.getTrackingUid(context) ?: run {
            SchedulePrefs.setLastPendingFlush(context, now.toString(), "skip:no_uid")
            return
        }

        val pendingResult = goAsync()
        Thread {
            try {
                Log.i(TAG, "flush pending start uid=$uid")
                SchedulePrefs.setLastPendingFlush(context, now.toString(), "start")
                val batch = TrackingDb.getPendingBatch(context, uid, 10)
                if (batch.isEmpty()) {
                    Log.i(TAG, "flush pending: sin pendientes uid=$uid")
                    SchedulePrefs.setLastPendingFlush(context, now.toString(), "empty")
                    AlarmScheduler.schedulePendingFlush(context)
                    return@Thread
                }
                val filtered = filterPendingBatch(context, batch)
                if (filtered.rejectedIds.isNotEmpty()) {
                    TrackingDb.deletePendingByIds(context, filtered.rejectedIds)
                }
                if (filtered.accepted.isEmpty()) {
                    Log.i(TAG, "flush pending: todos filtrados uid=$uid rejected=${filtered.rejectedIds.size}")
                    SchedulePrefs.setLastPendingFlush(
                        context,
                        now.toString(),
                        "filtered_empty:${filtered.rejectedIds.size}",
                    )
                    AlarmScheduler.schedulePendingFlush(context)
                    return@Thread
                }
                val ok = PendingLocationApiClient.sendBatch(
                    apiBaseUrl = apiBase,
                    bearerToken = token,
                    locations = filtered.accepted,
                )
                if (ok) {
                    Log.i(TAG, "flush pending ok uid=$uid count=${filtered.accepted.size}")
                    SchedulePrefs.setLastPendingFlush(
                        context,
                        now.toString(),
                        "ok:${filtered.accepted.size}",
                    )
                    TrackingDb.deletePendingByIds(context, filtered.accepted.map { it.id })
                } else {
                    Log.w(TAG, "flush pending failed uid=$uid count=${filtered.accepted.size}")
                    SchedulePrefs.setLastPendingFlush(context, now.toString(), "error")
                }
            } catch (e: Exception) {
                Log.w(TAG, "flush pending failed", e)
                SchedulePrefs.setLastPendingFlush(context, now.toString(), "error")
            } finally {
                try {
                    AlarmScheduler.schedulePendingFlush(context)
                } catch (_: Exception) {}
                pendingResult.finish()
            }
        }.start()
    }

    internal data class FilterResult(
        val accepted: List<TrackingDb.PendingLocationRow>,
        val rejectedIds: List<Long>,
    )

    private fun filterPendingBatch(context: Context, rows: List<TrackingDb.PendingLocationRow>): FilterResult =
        filterPendingBatch(
            rows = rows,
            prefs = SchedulePrefs.prefs(context),
            nowMs = System.currentTimeMillis(),
        )

    internal fun filterPendingBatch(
        rows: List<TrackingDb.PendingLocationRow>,
        prefs: android.content.SharedPreferences,
        nowMs: Long,
    ): FilterResult {
        if (rows.isEmpty()) return FilterResult(emptyList(), emptyList())

        fun getFlutterInt(key: String, defaultValue: Int): Int {
            val k = "flutter.$key"
            if (!prefs.contains(k)) return defaultValue
            return prefs.getLong(k, defaultValue.toLong()).toInt()
        }
        fun getFlutterDouble(key: String, defaultValue: Double): Double {
            val k = "flutter.$key"
            if (!prefs.contains(k)) return defaultValue
            val raw = prefs.getLong(k, java.lang.Double.doubleToRawLongBits(defaultValue))
            return java.lang.Double.longBitsToDouble(raw)
        }
        fun getFlutterBool(key: String, defaultValue: Boolean): Boolean {
            val k = "flutter.$key"
            if (!prefs.contains(k)) return defaultValue
            return prefs.getBoolean(k, defaultValue)
        }

        val stillInterval = getFlutterInt("tracking_still_interval_s", 30)
        val stillDistance = getFlutterDouble("tracking_still_min_dist_m", 10.0)
        val forceAccept = getFlutterInt("tracking_force_accept_s", 300)
        val maxAccuracy = getFlutterDouble("tracking_max_accuracy_m", 20.0)
        val filtersEnabled = getFlutterBool("tracking_filters_enabled", true)

        val maxStaleSeconds = 180
        val stillSpeedMps = 1.0
        val walkingSpeedMps = 2.5
        val minIntervalWalking = 5
        val minIntervalVehicle = 3
        val minDistanceWalking = 12.0
        val minDistanceVehicle = 40.0
        val maxSpeedWalking = 2.0 // ~7.2 km/h
        val maxSpeedVehicle = 27.7777777778 // 100 km/h
        val maxJumpWalking = 120.0
        val maxJumpVehicle = 500.0
        val maxJumpWindowSeconds = 10
        val maxKalmanGapSeconds = 60

        val accepted = mutableListOf<TrackingDb.PendingLocationRow>()
        val rejectedIds = mutableListOf<Long>()
        var lastAccepted: TrackingDb.PendingLocationRow? = null
        var refLat: Double? = null
        var refLng: Double? = null
        var kalmanX: Kalman1D? = null
        var kalmanY: Kalman1D? = null
        var lastKalmanAtMs: Long? = null

        fun distanceMeters(
            lat1: Double,
            lon1: Double,
            lat2: Double,
            lon2: Double,
        ): Double {
            val r = 6371000.0
            val dLat = Math.toRadians(lat2 - lat1)
            val dLon = Math.toRadians(lon2 - lon1)
            val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) *
                Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
            val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
            return r * c
        }

        fun minIntervalForSpeed(speed: Double): Int =
            when {
                speed <= stillSpeedMps -> stillInterval
                speed < walkingSpeedMps -> minIntervalWalking
                else -> minIntervalVehicle
            }

        fun minDistanceForSpeed(speed: Double): Double =
            when {
                speed <= stillSpeedMps -> stillDistance
                speed < walkingSpeedMps -> minDistanceWalking
                else -> minDistanceVehicle
            }

        fun maxSpeedForSpeed(speed: Double): Double =
            if (speed < walkingSpeedMps) maxSpeedWalking else maxSpeedVehicle

        fun maxJumpForSpeed(speed: Double): Double =
            if (speed < walkingSpeedMps) maxJumpWalking else maxJumpVehicle

        fun applyKalman(row: TrackingDb.PendingLocationRow): TrackingDb.PendingLocationRow {
            val accuracy = if (row.accuracy > 0) row.accuracy else 25.0
            if (refLat == null || refLng == null || kalmanX == null || kalmanY == null) {
                refLat = row.latitude
                refLng = row.longitude
                kalmanX = Kalman1D()
                kalmanY = Kalman1D()
                kalmanX!!.reset(0.0, accuracy)
                kalmanY!!.reset(0.0, accuracy)
                lastKalmanAtMs = row.timestampEpochMs
                return row
            }
            val dt = if (lastKalmanAtMs == null) 0.0
            else (row.timestampEpochMs - lastKalmanAtMs!!).toDouble() / 1000.0
            if (dt <= 0.0 || dt > maxKalmanGapSeconds) {
                refLat = row.latitude
                refLng = row.longitude
                kalmanX!!.reset(0.0, accuracy)
                kalmanY!!.reset(0.0, accuracy)
                lastKalmanAtMs = row.timestampEpochMs
                return row
            }
            val metersPerDegLat = 111320.0
            val metersPerDegLon = metersPerDegLat * Math.cos(Math.toRadians(refLat!!))
            val x = (row.longitude - refLng!!) * metersPerDegLon
            val y = (row.latitude - refLat!!) * metersPerDegLat
            val filteredX = kalmanX!!.update(x, accuracy, dt)
            val filteredY = kalmanY!!.update(y, accuracy, dt)
            val filteredLat = refLat!! + (filteredY / metersPerDegLat)
            val filteredLng = refLng!! + (filteredX / metersPerDegLon)
            lastKalmanAtMs = row.timestampEpochMs
            return row.copy(latitude = filteredLat, longitude = filteredLng)
        }

        if (!filtersEnabled) {
            val kalmanApplied = rows.map { row -> applyKalman(row) }
            return FilterResult(kalmanApplied, emptyList())
        }

        for (row in rows) {
            val filteredRow = applyKalman(row)
            val ageSec = ((nowMs - row.timestampEpochMs) / 1000).toInt()
            if (ageSec > maxStaleSeconds) {
                rejectedIds.add(filteredRow.id)
                continue
            }
            val prev = lastAccepted
            if (prev != null) {
                val dt = (filteredRow.timestampEpochMs - prev.timestampEpochMs) / 1000.0
                val sameInstant = filteredRow.latitude == prev.latitude &&
                    filteredRow.longitude == prev.longitude &&
                    filteredRow.timestampEpochMs == prev.timestampEpochMs
                if (sameInstant) {
                    rejectedIds.add(filteredRow.id)
                    continue
                }
                if (dt <= 0) {
                    rejectedIds.add(filteredRow.id)
                    continue
                }
                if (filteredRow.latitude == prev.latitude &&
                    filteredRow.longitude == prev.longitude &&
                    dt < 10.0
                ) {
                    rejectedIds.add(filteredRow.id)
                    continue
                }
                if (dt >= forceAccept) {
                    accepted.add(filteredRow)
                    lastAccepted = filteredRow
                    continue
                }
                val dist = distanceMeters(prev.latitude, prev.longitude, filteredRow.latitude, filteredRow.longitude)
                val derivedSpeed = if (filteredRow.speed > 0) filteredRow.speed else dist / dt
                val minInterval = minIntervalForSpeed(derivedSpeed)
                val minDistance = minDistanceForSpeed(derivedSpeed)
                if (dt < minInterval && dist < minDistance) {
                    rejectedIds.add(filteredRow.id)
                    continue
                }
                val impliedSpeed = dist / dt
                if (impliedSpeed > maxSpeedForSpeed(derivedSpeed)) {
                    rejectedIds.add(filteredRow.id)
                    continue
                }
                if (dt <= maxJumpWindowSeconds) {
                    val maxJump = maxJumpForSpeed(derivedSpeed)
                    if (dist > maxJump) {
                        rejectedIds.add(filteredRow.id)
                        continue
                    }
                }
            }
            if (filteredRow.accuracy > maxAccuracy) {
                rejectedIds.add(filteredRow.id)
                continue
            }
            accepted.add(filteredRow)
            lastAccepted = filteredRow
        }
        return FilterResult(accepted, rejectedIds)
    }

    internal class Kalman1D {
        private var p = 1.0
        fun reset(measurement: Double, accuracy: Double) {
            p = accuracy * accuracy
        }
        fun update(measurement: Double, accuracy: Double, dt: Double): Double {
            if (dt <= 0.0) {
                reset(measurement, accuracy)
                return measurement
            }
            val q = Math.max(1.0, accuracy) * 0.001
            p += q
            val r = accuracy * accuracy
            val k = p / (p + r)
            p = (1 - k) * p
            return measurement
        }
    }
}
