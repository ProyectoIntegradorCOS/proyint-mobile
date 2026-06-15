package com.example.flutter_application_1.tracking

import android.content.Context
import androidx.test.core.app.ApplicationProvider
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
class TrackingDbTest {
    private lateinit var context: Context
    private var nowMs: Long = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase("tracking_store.db")
        nowMs = System.currentTimeMillis()
    }

    @After
    fun tearDown() {
        context.deleteDatabase("tracking_store.db")
    }

    @Test
    fun `insertPendingLocation stores rows and getPendingBatch returns them in order`() {
        TrackingDb.insertPendingLocation(
            context = context,
            saaSubject = "uid-123",
            latitude = -12.0464,
            longitude = -77.0428,
            timestampIso = "2026-03-12T10:00:00-05:00",
            timestampEpochMs = nowMs - 10_000L,
            accuracy = 8.0,
            altitude = 120.0,
            speed = 1.2,
            heading = 35.0,
            batteryLevel = 85.0,
            activityType = "walking",
        )
        TrackingDb.insertPendingLocation(
            context = context,
            saaSubject = "uid-123",
            latitude = -12.0465,
            longitude = -77.0429,
            timestampIso = "2026-03-12T10:00:10-05:00",
            timestampEpochMs = nowMs - 5_000L,
            accuracy = 7.0,
            altitude = 121.0,
            speed = 1.0,
            heading = 30.0,
            batteryLevel = 84.0,
            activityType = "walking",
        )

        val rows = TrackingDb.getPendingBatch(context, "uid-123", limit = 10)

        assertEquals(2, rows.size)
        assertEquals("uid-123", rows[0].saaSubject)
        assertTrue(rows[0].id < rows[1].id)
        assertEquals(-12.0464, rows[0].latitude, 0.0)
        assertEquals(-12.0465, rows[1].latitude, 0.0)
    }

    @Test
    fun `countPendingForSubject reflects inserted and deleted rows`() {
        TrackingDb.insertPendingLocation(
            context = context,
            saaSubject = "uid-123",
            latitude = -12.0464,
            longitude = -77.0428,
            timestampIso = "2026-03-12T10:00:00-05:00",
            timestampEpochMs = nowMs - 10_000L,
            accuracy = 8.0,
            altitude = 120.0,
            speed = 1.2,
            heading = 35.0,
            batteryLevel = 85.0,
            activityType = "walking",
        )
        TrackingDb.insertPendingLocation(
            context = context,
            saaSubject = "uid-123",
            latitude = -12.0465,
            longitude = -77.0429,
            timestampIso = "2026-03-12T10:00:10-05:00",
            timestampEpochMs = nowMs - 5_000L,
            accuracy = 7.0,
            altitude = 121.0,
            speed = 1.0,
            heading = 30.0,
            batteryLevel = 84.0,
            activityType = "walking",
        )

        val ids = TrackingDb.getPendingBatch(context, "uid-123", limit = 10).map { it.id }
        assertEquals(2, TrackingDb.countPendingForSubject(context, "uid-123"))

        TrackingDb.deletePendingByIds(context, ids.take(1))

        assertEquals(1, TrackingDb.countPendingForSubject(context, "uid-123"))
    }

    @Test
    fun `getPendingBatch respects subject isolation and limit`() {
        repeat(3) { index ->
            TrackingDb.insertPendingLocation(
                context = context,
                saaSubject = "uid-123",
                latitude = -12.0464 + index,
                longitude = -77.0428,
                timestampIso = "2026-03-12T10:00:0$index-05:00",
                timestampEpochMs = nowMs - 10_000L + index,
                accuracy = 8.0,
                altitude = 120.0,
                speed = 1.2,
                heading = 35.0,
                batteryLevel = 85.0,
                activityType = "walking",
            )
        }
        TrackingDb.insertPendingLocation(
            context = context,
            saaSubject = "uid-999",
            latitude = -11.0,
            longitude = -76.0,
            timestampIso = "2026-03-12T11:00:00-05:00",
            timestampEpochMs = nowMs - 1_000L,
            accuracy = 5.0,
            altitude = 100.0,
            speed = 0.0,
            heading = 0.0,
            batteryLevel = 90.0,
            activityType = "still",
        )

        val rows = TrackingDb.getPendingBatch(context, "uid-123", limit = 2)

        assertEquals(2, rows.size)
        assertTrue(rows.all { it.saaSubject == "uid-123" })
    }
}
