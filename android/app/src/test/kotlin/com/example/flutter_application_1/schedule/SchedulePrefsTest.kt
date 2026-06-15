package com.example.flutter_application_1.schedule

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SchedulePrefsTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        SchedulePrefs.prefs(context).edit().clear().commit()
    }

    @After
    fun tearDown() {
        SchedulePrefs.prefs(context).edit().clear().commit()
    }

    @Test
    fun `getStoredSchedule returns null when schedule is missing`() {
        assertNull(SchedulePrefs.getStoredSchedule(context))
    }

    @Test
    fun `storeSchedule persists schedule data`() {
        val schedule = StoredSchedule(horarioId = 12L, startHour = 8, endHour = 17)

        SchedulePrefs.storeSchedule(context, schedule)

        assertEquals(schedule, SchedulePrefs.getStoredSchedule(context))
    }

    @Test
    fun `getStoredSchedule returns null when stored values are invalid`() {
        SchedulePrefs.prefs(context).edit()
            .putLong("flutter.bg_horario_id", 99L)
            .putLong("flutter.bg_hora_inicio", 8L)
            .putLong("flutter.bg_hora_fin", 25L)
            .commit()

        assertNull(SchedulePrefs.getStoredSchedule(context))
    }

    @Test
    fun `tracking uid roundtrip works`() {
        assertNull(SchedulePrefs.getTrackingUid(context))

        SchedulePrefs.setTrackingUid(context, "uid-123")

        assertEquals("uid-123", SchedulePrefs.getTrackingUid(context))
    }

    @Test
    fun `foreground tracking flag roundtrip works`() {
        assertFalse(SchedulePrefs.isForegroundTrackingActive(context))

        SchedulePrefs.setForegroundTrackingActive(context, true)

        assertTrue(SchedulePrefs.isForegroundTrackingActive(context))
    }

    @Test
    fun `native telemetry roundtrip works`() {
        SchedulePrefs.setNativeLastPoint(context, lat = -12.0464, lng = -77.0428, count = 7)

        assertEquals(-12.0464, SchedulePrefs.getNativeLastLat(context)!!, 0.0)
        assertEquals(-77.0428, SchedulePrefs.getNativeLastLng(context)!!, 0.0)
        assertEquals(7, SchedulePrefs.getNativeSqliteCount(context))
    }

    @Test
    fun `arrival target values are parsed from flutter preferences`() {
        SchedulePrefs.prefs(context).edit()
            .putBoolean("flutter.arrival_target_enabled", true)
            .putString("flutter.arrival_target_lat", "-12.0464")
            .putString("flutter.arrival_target_lng", "-77.0428")
            .putString("flutter.arrival_target_radius_m", "35.5")
            .commit()

        assertTrue(SchedulePrefs.isArrivalTargetEnabled(context))
        assertEquals(-12.0464, SchedulePrefs.getArrivalTargetLat(context)!!, 0.0)
        assertEquals(-77.0428, SchedulePrefs.getArrivalTargetLng(context)!!, 0.0)
        assertEquals(35.5, SchedulePrefs.getArrivalTargetRadius(context)!!, 0.0)
    }
}
