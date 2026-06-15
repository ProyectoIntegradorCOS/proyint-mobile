// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:45 UTC-5 (Lima)][desc: Cliente HTTP nativo para enviar batch de ubicaciones pendientes][obj: PendingLocationApiClient]
package com.example.flutter_application_1.tracking

import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

object PendingLocationApiClient {
    fun sendBatch(
        apiBaseUrl: String,
        bearerToken: String,
        locations: List<TrackingDb.PendingLocationRow>,
    ): Boolean {
        if (locations.isEmpty()) return true
        val normalizedBase = apiBaseUrl.trim().trimEnd('/')
        val url = "$normalizedBase/locations/batch"
        val payload = JSONObject()
        val arr = JSONArray()
        for (row in locations) {
            val obj = JSONObject()
            obj.put("saaSubject", row.saaSubject)
            obj.put("latitude", row.latitude)
            obj.put("longitude", row.longitude)
            obj.put("timestamp", row.timestamp)
            obj.put("accuracy", row.accuracy)
            obj.put("altitude", row.altitude)
            obj.put("speed", row.speed)
            obj.put("heading", row.heading)
            obj.put("batteryLevel", row.batteryLevel.toInt())
            obj.put("activityType", row.activityType)
            arr.put(obj)
        }
        payload.put("locations", arr)

        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", "Bearer $bearerToken")
            connectTimeout = 10_000
            readTimeout = 10_000
            doOutput = true
        }
        return try {
            OutputStreamWriter(conn.outputStream).use { it.write(payload.toString()) }
            val code = conn.responseCode
            code in 200..299
        } catch (_: Exception) {
            false
        } finally {
            conn.disconnect()
        }
    }
}
