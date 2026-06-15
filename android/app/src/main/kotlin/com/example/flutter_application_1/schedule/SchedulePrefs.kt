// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Acceso centralizado a preferencias para scheduler de tracking en background][obj: SchedulePrefs]
package com.example.flutter_application_1.schedule

import android.content.Context
import android.content.SharedPreferences
import com.example.flutter_application_1.security.SecurePrefs

data class StoredSchedule(
    val horarioId: Long,
    val startHour: Int,
    val endHour: Int,
)

object SchedulePrefs {
    // shared_preferences (Flutter) persiste en este archivo y prefija keys con "flutter."
    private const val FLUTTER_PREFS_FILE = "FlutterSharedPreferences"
    private const val FLUTTER_PREFIX = "flutter."

    private const val KEY_API_BASE_URL = "${FLUTTER_PREFIX}api_base_url"
    private const val KEY_AUTH_TOKEN = "${FLUTTER_PREFIX}auth_token"
    private const val KEY_AUTH_UID = "${FLUTTER_PREFIX}auth_uid"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: tracking_uid persiste aun con logout real; usado por tracking nativo por horario][obj: SchedulePrefs tracking_uid]
    private const val KEY_TRACKING_UID = "${FLUTTER_PREFIX}tracking_uid"

    private const val KEY_BG_HORARIO_ID = "${FLUTTER_PREFIX}bg_horario_id"
    private const val KEY_BG_HORA_INICIO = "${FLUTTER_PREFIX}bg_hora_inicio"
    private const val KEY_BG_HORA_FIN = "${FLUTTER_PREFIX}bg_hora_fin"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:42 UTC-5 (Lima)][desc: Guarda traza del último flush nativo de pendientes][obj: SchedulePrefs bg_flush_last]
    private const val KEY_BG_FLUSH_LAST_AT = "${FLUTTER_PREFIX}bg_flush_last_at"
    private const val KEY_BG_FLUSH_LAST_STATUS = "${FLUTTER_PREFIX}bg_flush_last_status"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Flag para evitar doble tracking (Flutter foreground vs servicio nativo)][obj: SchedulePrefs fg_tracking_active]
    private const val KEY_FG_TRACKING_ACTIVE = "${FLUTTER_PREFIX}fg_tracking_active"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Flag nativeAlwaysOn: si true, el servicio nativo debe correr incluso con Flutter activo en foreground][obj: SchedulePrefs native_always_on]
    private const val KEY_NATIVE_ALWAYS_ON = "${FLUTTER_PREFIX}tracking_native_always_on"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Telemetría nativa: último punto capturado y conteo de pendientes en SQLite][obj: SchedulePrefs native telemetry]
    private const val KEY_NATIVE_LAST_LAT = "${FLUTTER_PREFIX}native_last_lat"
    private const val KEY_NATIVE_LAST_LNG = "${FLUTTER_PREFIX}native_last_lng"
    private const val KEY_NATIVE_SQLITE_COUNT = "${FLUTTER_PREFIX}native_sqlite_count"
    private const val KEY_ACTIVE_LOG_PATH = "${FLUTTER_PREFIX}active_log_path"
    private const val KEY_APP_IN_FOREGROUND = "${FLUTTER_PREFIX}app_in_foreground"

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-23 UTC-5 (Lima)][desc: Target de llegada para alertas nativas][obj: SchedulePrefs arrival target]
    private const val KEY_ARRIVAL_ENABLED = "${FLUTTER_PREFIX}arrival_target_enabled"
    private const val KEY_ARRIVAL_LAT = "${FLUTTER_PREFIX}arrival_target_lat"
    private const val KEY_ARRIVAL_LNG = "${FLUTTER_PREFIX}arrival_target_lng"
    private const val KEY_ARRIVAL_RADIUS = "${FLUTTER_PREFIX}arrival_target_radius_m"
    private const val KEY_ARRIVAL_LAST_ALERT = "${FLUTTER_PREFIX}arrival_last_alert_ms"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Contador de alertas disparadas para el destino actual; se deshabilita tras MAX_ARRIVAL_ALERTS][obj: SchedulePrefs arrival alert count]
    private const val KEY_ARRIVAL_ALERT_COUNT = "${FLUTTER_PREFIX}arrival_alert_count"

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FLUTTER_PREFS_FILE, Context.MODE_PRIVATE)

    fun getApiBaseUrl(context: Context): String? =
        prefs(context).getString(KEY_API_BASE_URL, null)

    fun getAuthToken(context: Context): String? =
        SecurePrefs.getAuthToken(context) ?: prefs(context).getString(KEY_AUTH_TOKEN, null)

    fun getAuthUid(context: Context): String? =
        prefs(context).getString(KEY_AUTH_UID, null)

    fun getTrackingUid(context: Context): String? =
        prefs(context).getString(KEY_TRACKING_UID, null)

    fun setTrackingUid(context: Context, uid: String) {
        prefs(context).edit().putString(KEY_TRACKING_UID, uid).apply()
    }

    fun isForegroundTrackingActive(context: Context): Boolean =
        prefs(context).getBoolean(KEY_FG_TRACKING_ACTIVE, false)

    fun setForegroundTrackingActive(context: Context, active: Boolean) {
        prefs(context).edit().putBoolean(KEY_FG_TRACKING_ACTIVE, active).apply()
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Lee flag nativeAlwaysOn desde SharedPreferences de Flutter][obj: SchedulePrefs.isNativeAlwaysOn]
    fun isNativeAlwaysOn(context: Context): Boolean =
        prefs(context).getBoolean(KEY_NATIVE_ALWAYS_ON, false)

    fun getStoredSchedule(context: Context): StoredSchedule? {
        val p = prefs(context)
        if (!p.contains(KEY_BG_HORARIO_ID) || !p.contains(KEY_BG_HORA_INICIO) || !p.contains(KEY_BG_HORA_FIN)) {
            return null
        }
        // shared_preferences almacena ints como Long en Android
        val horarioId = p.getLong(KEY_BG_HORARIO_ID, -1L)
        val start = p.getLong(KEY_BG_HORA_INICIO, -1L).toInt()
        val end = p.getLong(KEY_BG_HORA_FIN, -1L).toInt()
        if (horarioId <= 0 || start !in 0..23 || end !in 0..23) return null
        return StoredSchedule(horarioId = horarioId, startHour = start, endHour = end)
    }

    fun storeSchedule(context: Context, schedule: StoredSchedule) {
        prefs(context).edit()
            .putLong(KEY_BG_HORARIO_ID, schedule.horarioId)
            .putLong(KEY_BG_HORA_INICIO, schedule.startHour.toLong())
            .putLong(KEY_BG_HORA_FIN, schedule.endHour.toLong())
            .apply()
    }

    fun setLastPendingFlush(context: Context, timestampIso: String, status: String) {
        prefs(context).edit()
            .putString(KEY_BG_FLUSH_LAST_AT, timestampIso)
            .putString(KEY_BG_FLUSH_LAST_STATUS, status)
            .apply()
    }

    fun getLastPendingFlushAt(context: Context): String? =
        prefs(context).getString(KEY_BG_FLUSH_LAST_AT, null)

    fun getLastPendingFlushStatus(context: Context): String? =
        prefs(context).getString(KEY_BG_FLUSH_LAST_STATUS, null)

    fun isArrivalTargetEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ARRIVAL_ENABLED, false)

    fun getArrivalTargetLat(context: Context): Double? =
        prefs(context).getString(KEY_ARRIVAL_LAT, null)?.toDoubleOrNull()

    fun getArrivalTargetLng(context: Context): Double? =
        prefs(context).getString(KEY_ARRIVAL_LNG, null)?.toDoubleOrNull()

    fun getArrivalTargetRadius(context: Context): Double? =
        prefs(context).getString(KEY_ARRIVAL_RADIUS, null)?.toDoubleOrNull()

    fun getArrivalLastAlertAt(context: Context): Long =
        prefs(context).getLong(KEY_ARRIVAL_LAST_ALERT, 0L)

    fun setArrivalLastAlertAt(context: Context, value: Long) {
        prefs(context).edit().putLong(KEY_ARRIVAL_LAST_ALERT, value).apply()
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Incrementa contador de alertas y devuelve el nuevo valor][obj: SchedulePrefs.incrementArrivalAlertCount]
    fun incrementArrivalAlertCount(context: Context): Int {
        val count = prefs(context).getInt(KEY_ARRIVAL_ALERT_COUNT, 0) + 1
        prefs(context).edit().putInt(KEY_ARRIVAL_ALERT_COUNT, count).apply()
        return count
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Deshabilita el target de llegada y resetea el contador; llamado tras MAX_ARRIVAL_ALERTS o al confirmar llegada desde Flutter][obj: SchedulePrefs.disableArrivalTarget]
    fun disableArrivalTarget(context: Context) {
        prefs(context).edit()
            .putBoolean(KEY_ARRIVAL_ENABLED, false)
            .putInt(KEY_ARRIVAL_ALERT_COUNT, 0)
            .apply()
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Guarda último punto nativo capturado y conteo de pendientes en SQLite para telemetría Flutter][obj: SchedulePrefs.setNativeLastPoint]
    fun setNativeLastPoint(context: Context, lat: Double, lng: Double, count: Int) {
        prefs(context).edit()
            .putLong(KEY_NATIVE_LAST_LAT, java.lang.Double.doubleToRawLongBits(lat))
            .putLong(KEY_NATIVE_LAST_LNG, java.lang.Double.doubleToRawLongBits(lng))
            .putInt(KEY_NATIVE_SQLITE_COUNT, count)
            .apply()
    }

    fun getNativeLastLat(context: Context): Double? {
        val bits = prefs(context).getLong(KEY_NATIVE_LAST_LAT, Long.MIN_VALUE)
        return if (bits == Long.MIN_VALUE) null else java.lang.Double.longBitsToDouble(bits)
    }

    fun getNativeLastLng(context: Context): Double? {
        val bits = prefs(context).getLong(KEY_NATIVE_LAST_LNG, Long.MIN_VALUE)
        return if (bits == Long.MIN_VALUE) null else java.lang.Double.longBitsToDouble(bits)
    }

    fun getNativeSqliteCount(context: Context): Int =
        prefs(context).getInt(KEY_NATIVE_SQLITE_COUNT, -1)

    fun getActiveLogPath(context: Context): String? =
        prefs(context).getString(KEY_ACTIVE_LOG_PATH, null)

    fun isAppInForeground(context: Context): Boolean =
        prefs(context).getBoolean(KEY_APP_IN_FOREGROUND, false)

    fun setAppInForeground(context: Context, active: Boolean) {
        prefs(context).edit().putBoolean(KEY_APP_IN_FOREGROUND, active).apply()
    }
}
