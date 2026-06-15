import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../utils/logger.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  final Battery _battery = Battery();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    logDebug('Foreground task iniciado');
    await _updateNotification();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    logDebug('Foreground task tick \${timestamp.toIso8601String()}');
    await _updateNotification();
  }

  Future<void> _updateNotification() async {
    int? batteryLevel;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}

    logDebug(
      'Actualizando notificación foreground',
      details: batteryLevel != null ? 'battery=$batteryLevel' : 'battery=?',
    );
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Sistema activo',
      notificationText: batteryLevel != null
          ? 'Batería: $batteryLevel%'
          : 'Registrando ubicación en background',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    logDebug('Foreground task destruido (timeout: $isTimeout). Liberando recursos...');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      logDebug('Usuario presionó detener en notificación.');
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}
