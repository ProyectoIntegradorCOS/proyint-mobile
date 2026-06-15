package com.example.flutter_application_1.schedule

import android.Manifest
import android.app.Application
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.example.flutter_application_1.tracking.LocationTrackingService
import org.junit.After
import org.junit.Assume.assumeTrue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.LocalDateTime
import java.time.ZoneId

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TrackingWindowEnforcerTest {
    private lateinit var application: Application

    @Before
    fun setUp() {
        application = ApplicationProvider.getApplicationContext()
        SchedulePrefs.prefs(application).edit().clear().commit()
    }

    @After
    fun tearDown() {
        SchedulePrefs.prefs(application).edit().clear().commit()
    }

    @Test
    fun `shouldRun returns true for weekday within configured window`() {
        val now = LocalDateTime.of(2026, 3, 12, 10, 0)
        val schedule = StoredSchedule(horarioId = 1L, startHour = 8, endHour = 20)

        assertTrue(TrackingWindowEnforcer.shouldRun(now, schedule))
    }

    @Test
    fun `shouldRun returns false for weekend`() {
        val now = LocalDateTime.of(2026, 3, 14, 10, 0)
        val schedule = StoredSchedule(horarioId = 1L, startHour = 8, endHour = 20)

        assertFalse(TrackingWindowEnforcer.shouldRun(now, schedule))
    }

    @Test
    fun `enforce stops native service when foreground tracking is active`() {
        SchedulePrefs.setTrackingUid(application, "uid-123")
        SchedulePrefs.storeSchedule(application, StoredSchedule(1L, 8, 20))
        SchedulePrefs.setForegroundTrackingActive(application, true)

        TrackingWindowEnforcer.enforce(application)

        val stoppedIntent = shadowOf(application).nextStoppedService
        assertNotNull(stoppedIntent)
        assertEquals(
            Intent(application, LocationTrackingService::class.java).component,
            stoppedIntent.component,
        )
    }

    @Test
    fun `enforce starts native service when within schedule and permissions are granted`() {
        val now = LocalDateTime.now(ZoneId.of("America/Lima"))
        assumeTrue(now.dayOfWeek.value in 1..5)

        shadowOf(application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.FOREGROUND_SERVICE_LOCATION,
        )
        SchedulePrefs.setTrackingUid(application, "uid-123")
        SchedulePrefs.storeSchedule(
            application,
            StoredSchedule(1L, now.hour, (now.hour + 1) % 24),
        )

        TrackingWindowEnforcer.enforce(application)

        val startedIntent = shadowOf(application).nextStartedService
        assertNotNull(startedIntent)
        assertEquals(
            Intent(application, LocationTrackingService::class.java).component,
            startedIntent.component,
        )
        assertEquals("uid-123", startedIntent.getStringExtra("tracking_uid"))
    }

    @Test
    fun `enforce aborts when tracking uid is missing`() {
        val now = LocalDateTime.now(ZoneId.of("America/Lima"))
        SchedulePrefs.storeSchedule(
            application,
            StoredSchedule(1L, now.hour, (now.hour + 1) % 24),
        )

        TrackingWindowEnforcer.enforce(application)

        assertNull(shadowOf(application).nextStartedService)
        assertNull(shadowOf(application).nextStoppedService)
    }
}
