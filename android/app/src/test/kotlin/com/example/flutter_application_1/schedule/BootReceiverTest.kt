package com.example.flutter_application_1.schedule

import android.app.AlarmManager
import android.app.Application
import android.content.Context
import android.content.Intent
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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BootReceiverTest {
    private lateinit var application: Application
    private lateinit var alarmManager: AlarmManager
    private lateinit var receiver: BootReceiver

    @Before
    fun setUp() {
        application = ApplicationProvider.getApplicationContext()
        alarmManager = application.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        receiver = BootReceiver()
        SchedulePrefs.prefs(application).edit().clear().commit()
        shadowOf(alarmManager).scheduledAlarms.clear()
        SchedulePrefs.storeSchedule(
            application,
            StoredSchedule(horarioId = 1L, startHour = 8, endHour = 20),
        )
    }

    @After
    fun tearDown() {
        SchedulePrefs.prefs(application).edit().clear().commit()
        shadowOf(alarmManager).scheduledAlarms.clear()
    }

    @Test
    fun `onReceive schedules alarms after boot completed`() {
        receiver.onReceive(application, Intent(Intent.ACTION_BOOT_COMPLETED))

        assertEquals(4, shadowOf(alarmManager).scheduledAlarms.size)
    }

    @Test
    fun `onReceive schedules alarms after package replaced`() {
        receiver.onReceive(application, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

        assertEquals(4, shadowOf(alarmManager).scheduledAlarms.size)
    }

    @Test
    fun `onReceive ignores unrelated actions`() {
        receiver.onReceive(application, Intent(Intent.ACTION_AIRPLANE_MODE_CHANGED))

        assertTrue(shadowOf(alarmManager).scheduledAlarms.isEmpty())
    }
}
