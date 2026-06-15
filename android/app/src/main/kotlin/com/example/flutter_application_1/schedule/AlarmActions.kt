// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Define acciones de AlarmManager para scheduler exacto de tracking][obj: AlarmActions]
package com.example.flutter_application_1.schedule

object AlarmActions {
    const val ACTION_REFRESH_BEFORE_START = "com.example.flutter_application_1.action.REFRESH_BEFORE_START"
    const val ACTION_START_TRACKING = "com.example.flutter_application_1.action.START_TRACKING"
    const val ACTION_REFRESH_BEFORE_END = "com.example.flutter_application_1.action.REFRESH_BEFORE_END"
    const val ACTION_STOP_TRACKING = "com.example.flutter_application_1.action.STOP_TRACKING"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:45 UTC-5 (Lima)][desc: Acción para flush de ubicaciones pendientes en background][obj: AlarmActions.ACTION_FLUSH_PENDING]
    const val ACTION_FLUSH_PENDING = "com.example.flutter_application_1.action.FLUSH_PENDING"
}
