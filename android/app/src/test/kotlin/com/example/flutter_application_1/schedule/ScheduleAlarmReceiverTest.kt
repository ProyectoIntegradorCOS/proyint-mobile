package com.example.flutter_application_1.schedule

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.flutter_application_1.tracking.TrackingDb
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ScheduleAlarmReceiverTest {
    private lateinit var context: Context
    private lateinit var receiver: ScheduleAlarmReceiver
    private lateinit var prefs: android.content.SharedPreferences
    private var nowMs: Long = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        prefs = SchedulePrefs.prefs(context)
        prefs.edit().clear().commit()
        receiver = ScheduleAlarmReceiver()
        nowMs = System.currentTimeMillis()
    }

    @After
    fun tearDown() {
        prefs.edit().clear().commit()
    }

    @Test
    fun `filterPendingBatch returns all rows when filters are disabled`() {
        prefs.edit()
            .putBoolean("flutter.tracking_filters_enabled", false)
            .commit()

        val rows = listOf(
            row(id = 1, timestampEpochMs = nowMs - 5_000L, accuracy = 50.0),
            row(id = 2, timestampEpochMs = nowMs - 2_000L, accuracy = 100.0),
        )

        val result = receiver.filterPendingBatch(rows = rows, prefs = prefs, nowMs = nowMs)

        assertEquals(2, result.accepted.size)
        assertTrue(result.rejectedIds.isEmpty())
    }

    @Test
    fun `filterPendingBatch rejects stale rows`() {
        val rows = listOf(
            row(id = 1, timestampEpochMs = nowMs - 181_000L),
            row(id = 2, timestampEpochMs = nowMs - 5_000L),
        )

        val result = receiver.filterPendingBatch(rows = rows, prefs = prefs, nowMs = nowMs)

        assertEquals(listOf(2L), result.accepted.map { it.id })
        assertEquals(listOf(1L), result.rejectedIds)
    }

    @Test
    fun `filterPendingBatch rejects poor accuracy beyond configured max`() {
        prefs.edit()
            .putLong(
                "flutter.tracking_max_accuracy_m",
                java.lang.Double.doubleToRawLongBits(20.0),
            )
            .commit()

        val rows = listOf(
            row(id = 1, timestampEpochMs = nowMs - 5_000L, accuracy = 10.0),
            row(id = 2, timestampEpochMs = nowMs - 1_000L, accuracy = 30.0),
        )

        val result = receiver.filterPendingBatch(rows = rows, prefs = prefs, nowMs = nowMs)

        assertEquals(listOf(1L), result.accepted.map { it.id })
        assertEquals(listOf(2L), result.rejectedIds)
    }

    @Test
    fun `filterPendingBatch rejects duplicate instant rows`() {
        val instant = nowMs - 5_000L
        val rows = listOf(
            row(id = 1, timestampEpochMs = instant, latitude = -12.0, longitude = -77.0),
            row(id = 2, timestampEpochMs = instant, latitude = -12.0, longitude = -77.0),
        )

        val result = receiver.filterPendingBatch(rows = rows, prefs = prefs, nowMs = nowMs)

        assertEquals(listOf(1L), result.accepted.map { it.id })
        assertEquals(listOf(2L), result.rejectedIds)
    }

    @Test
    fun `filterPendingBatch rejects near duplicate rows under still thresholds`() {
        prefs.edit()
            .putLong("flutter.tracking_still_interval_s", 30L)
            .putLong(
                "flutter.tracking_still_min_dist_m",
                java.lang.Double.doubleToRawLongBits(10.0),
            )
            .commit()

        val rows = listOf(
            row(id = 1, timestampEpochMs = nowMs - 10_000L, latitude = -12.0, longitude = -77.0, speed = 0.1),
            row(id = 2, timestampEpochMs = nowMs - 5_000L, latitude = -12.00001, longitude = -77.00001, speed = 0.1),
        )

        val result = receiver.filterPendingBatch(rows = rows, prefs = prefs, nowMs = nowMs)

        assertEquals(listOf(1L), result.accepted.map { it.id })
        assertEquals(listOf(2L), result.rejectedIds)
    }

    private fun row(
        id: Long,
        timestampEpochMs: Long,
        latitude: Double = -12.0464,
        longitude: Double = -77.0428,
        accuracy: Double = 8.0,
        speed: Double = 1.2,
    ): TrackingDb.PendingLocationRow = TrackingDb.PendingLocationRow(
        id = id,
        saaSubject = "uid-123",
        latitude = latitude,
        longitude = longitude,
        timestamp = "2026-03-12T10:00:00-05:00",
        timestampEpochMs = timestampEpochMs,
        accuracy = accuracy,
        altitude = 120.0,
        speed = speed,
        heading = 35.0,
        batteryLevel = 80.0,
        activityType = "walking",
    )
}
