package com.example.flutter_application_1.schedule

import android.app.AlarmManager
import android.app.Application
import android.content.Context
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
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
class AlarmSchedulerTest {
    private lateinit var application: Application
    private lateinit var alarmManager: AlarmManager

    @Before
    fun setUp() {
        application = ApplicationProvider.getApplicationContext()
        alarmManager = application.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        SchedulePrefs.prefs(application).edit().clear().commit()
        shadowOf(alarmManager).scheduledAlarms.clear()
    }

    @After
    fun tearDown() {
        SchedulePrefs.prefs(application).edit().clear().commit()
        shadowOf(alarmManager).scheduledAlarms.clear()
    }

    @Test
    fun `scheduleAll schedules one near refresh when no schedule exists`() {
        AlarmScheduler.scheduleAll(application)

        val alarms = shadowOf(alarmManager).scheduledAlarms

        assertEquals(1, alarms.size)
        val scheduledIntent = shadowOf(alarms.single().operation).savedIntent
        assertEquals(AlarmActions.ACTION_REFRESH_BEFORE_START, scheduledIntent.action)
        val deltaMs = alarms.single().triggerAtTime - System.currentTimeMillis()
        assertTrue(deltaMs in 30_000L..90_000L)
    }

    @Test
    fun `scheduleAll programs four actions for a persisted schedule`() {
        val now = LocalDateTime.now(ZoneId.of("America/Lima"))
        val startHour = now.plusHours(2).hour
        val endHour = now.plusHours(5).hour
        SchedulePrefs.storeSchedule(
            application,
            StoredSchedule(horarioId = 1L, startHour = startHour, endHour = endHour),
        )

        AlarmScheduler.scheduleAll(application)

        val alarms = shadowOf(alarmManager).scheduledAlarms
        val actions = alarms
            .map { alarm -> shadowOf(alarm.operation).savedIntent.action.orEmpty() }
            .sorted()

        assertEquals(4, alarms.size)
        assertEquals(
            listOf(
                AlarmActions.ACTION_REFRESH_BEFORE_END,
                AlarmActions.ACTION_REFRESH_BEFORE_START,
                AlarmActions.ACTION_START_TRACKING,
                AlarmActions.ACTION_STOP_TRACKING,
            ),
            actions,
        )
    }

    @Test
    fun `cancelAll removes scheduled tracking alarms`() {
        SchedulePrefs.storeSchedule(
            application,
            StoredSchedule(horarioId = 1L, startHour = 8, endHour = 20),
        )
        AlarmScheduler.scheduleAll(application)

        AlarmScheduler.cancelAll(application)

        assertTrue(shadowOf(alarmManager).scheduledAlarms.isEmpty())
    }

    @Test
    fun `schedulePendingFlush programs flush action after requested delay`() {
        val before = System.currentTimeMillis()

        AlarmScheduler.schedulePendingFlush(application, delayMinutes = 3)

        val alarm = shadowOf(alarmManager).scheduledAlarms.single()
        assertEquals(AlarmActions.ACTION_FLUSH_PENDING, shadowOf(alarm.operation).savedIntent.action)
        val expected = before + 3 * 60_000L
        val drift = kotlin.math.abs(alarm.triggerAtTime - expected)
        assertTrue(drift < 5_000L)
    }

    @Test
    fun `cancelPendingFlush removes flush alarm`() {
        AlarmScheduler.schedulePendingFlush(application, delayMinutes = 2)

        AlarmScheduler.cancelPendingFlush(application)

        assertTrue(shadowOf(alarmManager).scheduledAlarms.isEmpty())
    }
}
