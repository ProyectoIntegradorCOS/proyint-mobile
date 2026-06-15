// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Inserción SQLite nativa en la misma DB usada por sqflite para encolar ubicaciones pendientes][obj: TrackingDb]
package com.example.flutter_application_1.tracking

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase

object TrackingDb {
    private const val DB_NAME = "tracking_store.db"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Política de retención/purga en SQLite nativa (15 días / 5000 filas por usuario)][obj: TrackingDb retention]
    private const val RETENTION_DAYS = 15
    private const val MAX_ROWS_PER_SUBJECT = 5000

    fun insertPendingLocation(
        context: Context,
        saaSubject: String,
        latitude: Double,
        longitude: Double,
        timestampIso: String,
        timestampEpochMs: Long,
        accuracy: Double,
        altitude: Double,
        speed: Double,
        heading: Double,
        batteryLevel: Double,
        activityType: String,
    ) {
        val dbFile = context.getDatabasePath(DB_NAME)
        dbFile.parentFile?.mkdirs()
        val db = SQLiteDatabase.openDatabase(
            dbFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY,
        )
        try {
            ensureSchema(db)
            val values = ContentValues().apply {
                put("saaSubject", saaSubject)
                put("latitude", latitude)
                put("longitude", longitude)
                put("timestamp", timestampIso)
                put("timestamp_epoch_ms", timestampEpochMs)
                put("accuracy", accuracy)
                put("altitude", altitude)
                put("speed", speed)
                put("heading", heading)
                put("batteryLevel", batteryLevel)
                put("activityType", activityType)
            }
            db.insert("pending_locations", null, values)
            // Purga best-effort para no crecer sin control cuando la app está cerrada.
            try {
                purgeForSubject(db, saaSubject)
            } catch (_: Exception) {}
        } finally {
            db.close()
        }
    }

    fun purgePendingLocations(context: Context, saaSubject: String) {
        val dbFile = context.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) return
        val db = SQLiteDatabase.openDatabase(
            dbFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE,
        )
        try {
            ensureSchema(db)
            purgeForSubject(db, saaSubject)
            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Purga global de puntos huérfanos (cualquier usuario) con más de 30 días al hacer STOP_TRACKING diario][obj: TrackingDb.purgePendingLocations orphan purge]
            purgeAllOlderThan(db, maxAgeDays = 30)
        } finally {
            db.close()
        }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Elimina filas de cualquier usuario con más de maxAgeDays días. Limpia puntos huérfanos cuando se comparte dispositivo entre usuarios.][obj: TrackingDb.purgeAllOlderThan]
    private fun purgeAllOlderThan(db: SQLiteDatabase, maxAgeDays: Int) {
        val cutoff = System.currentTimeMillis() - (maxAgeDays * 24L * 60L * 60L * 1000L)
        db.delete(
            "pending_locations",
            "timestamp_epoch_ms IS NOT NULL AND timestamp_epoch_ms < ?",
            arrayOf(cutoff.toString()),
        )
    }

    data class PendingLocationRow(
        val id: Long,
        val saaSubject: String,
        val latitude: Double,
        val longitude: Double,
        val timestamp: String,
        val timestampEpochMs: Long,
        val accuracy: Double,
        val altitude: Double,
        val speed: Double,
        val heading: Double,
        val batteryLevel: Double,
        val activityType: String,
    )

    fun getPendingBatch(context: Context, saaSubject: String, limit: Int): List<PendingLocationRow> {
        val dbFile = context.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) return emptyList()
        val db = SQLiteDatabase.openDatabase(
            dbFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READONLY,
        )
        try {
            ensureSchema(db)
            val cursor = db.query(
                "pending_locations",
                arrayOf(
                    "id",
                    "saaSubject",
                    "latitude",
                    "longitude",
                    "timestamp",
                    "timestamp_epoch_ms",
                    "accuracy",
                    "altitude",
                    "speed",
                    "heading",
                    "batteryLevel",
                    "activityType",
                ),
                "saaSubject = ?",
                arrayOf(saaSubject),
                null,
                null,
                "id ASC",
                limit.toString(),
            )
            val rows = mutableListOf<PendingLocationRow>()
            cursor.use {
                while (it.moveToNext()) {
                    rows.add(
                        PendingLocationRow(
                            id = it.getLong(0),
                            saaSubject = it.getString(1),
                            latitude = it.getDouble(2),
                            longitude = it.getDouble(3),
                            timestamp = it.getString(4),
                            timestampEpochMs = it.getLong(5),
                            accuracy = it.getDouble(6),
                            altitude = it.getDouble(7),
                            speed = it.getDouble(8),
                            heading = it.getDouble(9),
                            batteryLevel = it.getDouble(10),
                            activityType = it.getString(11),
                        )
                    )
                }
            }
            return rows
        } finally {
            db.close()
        }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Cuenta puntos pendientes en SQLite nativo para telemetría][obj: TrackingDb.countPendingForSubject]
    fun countPendingForSubject(context: Context, saaSubject: String): Int {
        val dbFile = context.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) return 0
        val db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
        try {
            ensureSchema(db)
            val cursor = db.rawQuery(
                "SELECT COUNT(*) FROM pending_locations WHERE saaSubject = ?",
                arrayOf(saaSubject),
            )
            return try {
                if (cursor.moveToFirst()) cursor.getInt(0) else 0
            } finally {
                cursor.close()
            }
        } finally {
            db.close()
        }
    }

    fun deletePendingByIds(context: Context, ids: List<Long>) {
        if (ids.isEmpty()) return
        val dbFile = context.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) return
        val db = SQLiteDatabase.openDatabase(
            dbFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE,
        )
        try {
            ensureSchema(db)
            val placeholders = ids.joinToString(",") { "?" }
            val args = ids.map { it.toString() }.toTypedArray()
            db.delete(
                "pending_locations",
                "id IN ($placeholders)",
                args,
            )
        } finally {
            db.close()
        }
    }

    private fun purgeForSubject(db: SQLiteDatabase, saaSubject: String) {
        val cutoff = System.currentTimeMillis() - (RETENTION_DAYS * 24L * 60L * 60L * 1000L)
        db.delete(
            "pending_locations",
            "saaSubject = ? AND timestamp_epoch_ms IS NOT NULL AND timestamp_epoch_ms < ?",
            arrayOf(saaSubject, cutoff.toString()),
        )

        val cursor = db.rawQuery(
            "SELECT COUNT(*) FROM pending_locations WHERE saaSubject = ?",
            arrayOf(saaSubject),
        )
        val count = try {
            if (cursor.moveToFirst()) cursor.getLong(0) else 0L
        } finally {
            cursor.close()
        }
        val excess = (count - MAX_ROWS_PER_SUBJECT).toInt()
        if (excess <= 0) return

        // Borra los más antiguos según epoch; si faltara epoch, cae al id.
        db.execSQL(
            """
            DELETE FROM pending_locations
            WHERE id IN (
              SELECT id FROM pending_locations
              WHERE saaSubject = ?
              ORDER BY COALESCE(timestamp_epoch_ms, 0) ASC, id ASC
              LIMIT $excess
            )
            """.trimIndent(),
            arrayOf(saaSubject),
        )
    }

    private fun ensureSchema(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS pending_locations(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              saaSubject TEXT,
              latitude REAL,
              longitude REAL,
              timestamp TEXT,
              timestamp_epoch_ms INTEGER,
              accuracy REAL,
              altitude REAL,
              speed REAL,
              heading REAL,
              batteryLevel REAL,
              activityType TEXT
            )
            """.trimIndent()
        )
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Asegura columna timestamp_epoch_ms sin log de error (verifica PRAGMA table_info)][obj: TrackingDb.ensureSchema alter]
        ensureEpochColumn(db)
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS geocoding_cache(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              latitude REAL,
              longitude REAL,
              address TEXT,
              timestamp INTEGER
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_geo_lat_lng ON geocoding_cache(latitude, longitude)")

        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Alinea user_version con sqflite (evita que Flutter trate la DB como nueva)][obj: TrackingDb.ensureSchema user_version]
        try {
            db.execSQL("PRAGMA user_version = 6")
        } catch (_: Exception) {}
    }

    private fun ensureEpochColumn(db: SQLiteDatabase) {
        val c = db.rawQuery("PRAGMA table_info(pending_locations)", null)
        var exists = false
        try {
            val nameIndex = c.getColumnIndex("name")
            while (c.moveToNext()) {
                val name = if (nameIndex >= 0) c.getString(nameIndex) else null
                if (name == "timestamp_epoch_ms") {
                    exists = true
                    break
                }
            }
        } finally {
            c.close()
        }
        if (exists) return
        db.execSQL("ALTER TABLE pending_locations ADD COLUMN timestamp_epoch_ms INTEGER")
    }
}
