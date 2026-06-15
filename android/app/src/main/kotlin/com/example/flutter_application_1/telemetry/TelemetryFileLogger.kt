package com.example.flutter_application_1.telemetry

import android.content.Context
import com.example.flutter_application_1.schedule.SchedulePrefs
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

object TelemetryFileLogger {
    private val filenameFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd_HH-mm-ss").withZone(ZoneOffset.ofHours(-5))
    private val lineFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm:ss").withZone(ZoneOffset.ofHours(-5))

    fun log(context: Context, message: String) {
        try {
            val file = resolveLogFile(context)
            file.parentFile?.mkdirs()
            file.appendText("[${lineFormatter.format(Instant.now())}] $message\n")
        } catch (_: Exception) {}
    }

    private fun resolveLogFile(context: Context): File {
        val activePath = SchedulePrefs.getActiveLogPath(context)
        if (!activePath.isNullOrBlank()) {
            return File(activePath)
        }

        val fallbackDir = context.getExternalFilesDir(null) ?: context.filesDir
        val fallbackName = "log_${filenameFormatter.format(Instant.now())}.txt"
        return File(fallbackDir, fallbackName)
    }
}
