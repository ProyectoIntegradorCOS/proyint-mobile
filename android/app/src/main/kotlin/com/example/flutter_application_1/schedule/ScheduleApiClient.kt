// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Cliente HTTP simple para refrescar horario desde backend usando Bearer token][obj: ScheduleApiClient]
package com.example.flutter_application_1.schedule

import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

object ScheduleApiClient {
    fun fetchScheduleFromBackend(
        apiBaseUrl: String,
        saaSubject: String,
        bearerToken: String,
    ): StoredSchedule? {
        val normalizedBase = apiBaseUrl.trim().trimEnd('/')
        val userJson = httpGetJson("$normalizedBase/users/$saaSubject", bearerToken) ?: return null
        val horarioId = userJson.optLong("horarioId", -1)
        if (horarioId <= 0) return null
        val horarioJson = httpGetJson("$normalizedBase/horarios/$horarioId", bearerToken) ?: return null
        val startHour = horarioJson.optInt("horaInicio", -1)
        val endHour = horarioJson.optInt("horaFin", -1)
        if (startHour !in 0..23 || endHour !in 0..23) return null
        return StoredSchedule(horarioId = horarioId, startHour = startHour, endHour = endHour)
    }

    private fun httpGetJson(url: String, bearerToken: String): JSONObject? {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", "Bearer $bearerToken")
            connectTimeout = 10_000
            readTimeout = 10_000
        }
        return try {
            val code = conn.responseCode
            if (code !in 200..299) {
                null
            } else {
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                JSONObject(body)
            }
        } catch (_: Exception) {
            null
        } finally {
            conn.disconnect()
        }
    }
}

