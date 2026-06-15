import 'dart:async';

import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'api_service.dart';
import 'location_sync_manager.dart';
import 'pending_location_store.dart';

// Task identifiers
const String kPendingFlushTask = 'pendingFlush';

@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      logDebug('WorkManager task start', details: task);

      if (task == kPendingFlushTask) {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Optimiza tarea background verificando conteo local primero][obj: backgroundTaskDispatcher]
        // [OPTIMIZATION] Check if there are pending locations before initializing heavy services
        final prefs = await SharedPreferences.getInstance();
        final uid = prefs.getString('auth_uid');
        if (uid == null || uid.isEmpty) {
          logDebug('WorkManager: Sin uid (auth_uid), no se flush para evitar mezclar sesiones.');
          return Future.value(true);
        }
        final store = PendingLocationStore();
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Flush en background se ejecuta por usuario (auth_uid)][obj: backgroundTaskDispatcher uid]
        final count = await store.countForSubject(uid);
        
        if (count == 0) {
          logDebug('WorkManager: Sin ubicaciones pendientes, finalizando.', details: 'uid=$uid');
          return Future.value(true);
        }

        logDebug('WorkManager: $count ubicaciones pendientes, iniciando sincronización.', details: 'uid=$uid');

        final token = await ApiService.loadSavedAuthToken();
        final api = ApiService();
        await api.updateAuthToken(token);
        final sync = LocationSyncManager(apiService: api, store: store);
        try {
          await sync.flushPending(firebaseUid: uid);
        } catch (e) {
          // Keep remaining queued; not a hard failure
          logError('Flush pending failed in background', error: e);
        } finally {
          api.dispose();
        }
      }

      return Future.value(true);
    } catch (e, st) {
      logError('WorkManager task error', error: e, stackTrace: st);
      return Future.value(false);
    }
  });
}

Future<void> registerBackgroundTasks() async {
  try {
    await Workmanager().cancelByUniqueName(kPendingFlushTask);
  } catch (_) {}
  await Workmanager().registerPeriodicTask(
    kPendingFlushTask,
    kPendingFlushTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    initialDelay: const Duration(minutes: 5),
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
  logDebug('WorkManager periodic flush registered');
}
