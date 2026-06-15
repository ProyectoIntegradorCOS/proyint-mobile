import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../utils/logger.dart';
import 'foreground_task_handler.dart';

class ForegroundServiceManager {
  ForegroundServiceManager();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    logDebug('Inicializando ForegroundServiceManager');
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracking_channel',
        channelName: 'Location Tracking',
        channelDescription: 'Mantiene el tracking activo en segundo plano',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        //iconData: const NotificationIconData(
        //  resType: ResourceType.mipmap,
        //  resPrefix: ResourcePrefix.ic,
        //  name: 'launcher',
        //),
        //buttons: const [NotificationButton(id: 'stop', text: 'Detener')],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      //foregroundTaskOptions: const ForegroundTaskOptions(
      foregroundTaskOptions: ForegroundTaskOptions(
        //interval: 60000,
        //isOnceEvent: false,
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:47 UTC-5 (Lima)][desc: Limita optimización de batería a Android; concepto no existe en iOS][obj: ForegroundServiceManager.init battery optimization guard]
    if (Platform.isAndroid) {
      final isIgnoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!isIgnoring) {
        logDebug('Solicitando ignorar optimizaciones de batería para estabilidad');
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }

    logDebug('ForegroundServiceManager inicializado y listo');
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Evita iniciar foreground service fuera de Android; en iOS el tracking background se resuelve por CLLocationManager][obj: ForegroundServiceManager.startService platform guard]
  Future<void> startService() async {
    if (!Platform.isAndroid) return;
    if (!_initialized) {
      await init();
    }
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) return;

    logDebug('Iniciando servicio foreground');
    await FlutterForegroundTask.startService(
      notificationTitle: 'Sistema activo',
      notificationText: 'La app está registrando tu ubicación',
      notificationIcon: null,
      // ✅ AGREGA estos parámetros aquí:
      /*notificationIcon: const AndroidNotificationIcon(
        //resType: ResourceType.mipmap,
        //resPrefix: ResourcePrefix.ic,
        resourceType: NotificationResourceType.mipmap,
        name: 'launcher',
      ),*/
      notificationButtons: const [
        NotificationButton(id: 'stop', text: 'Detener'),
      ],

      callback: startCallback,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Evita detener foreground service fuera de Android; en iOS no existe equivalente directo][obj: ForegroundServiceManager.stopService platform guard]
  Future<void> stopService() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      logDebug('Deteniendo servicio foreground');
      await FlutterForegroundTask.stopService();
    }
  }
}

//}
