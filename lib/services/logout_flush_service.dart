// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Fuerza envío de ubicaciones pendientes antes de cerrar sesión (sin esperar a completar batch)][obj: LogoutFlushService]
import '../utils/logger.dart';
import 'api_service.dart';
import 'location_sync_manager.dart';

class LogoutFlushService {
  LogoutFlushService._();

  static Future<void> flushPendingBeforeLogout({
    required String uid,
    required String token,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final api = ApiService(timeout: timeout);
    try {
      logInfo('Logout flush: inicio');
      await api.updateAuthToken(token);
      final sync = LocationSyncManager(apiService: api);
      await sync.flushPending(firebaseUid: uid);
      logInfo('Logout flush: fin');
    } catch (e, st) {
      logError('Logout flush: error', error: e, stackTrace: st);
    } finally {
      api.dispose();
    }
  }
}
