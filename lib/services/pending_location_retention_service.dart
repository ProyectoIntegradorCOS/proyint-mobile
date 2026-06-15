// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Retención/purga de ubicaciones pendientes (15 días / 5000 registros por usuario)][obj: PendingLocationRetentionService]
import '../utils/logger.dart';
import 'pending_location_store.dart';

class PendingLocationRetentionService {
  PendingLocationRetentionService({
    PendingLocationStore? store,
    this.maxAgeDays = 15,
    this.maxRowsPerUser = 5000,
  }) : _store = store ?? PendingLocationStore();

  final PendingLocationStore _store;
  final int maxAgeDays;
  final int maxRowsPerUser;

  Future<void> purgeForUser(String uid) async {
    try {
      await _store.purgeForSubject(
        uid,
        maxAge: Duration(days: maxAgeDays),
        maxRows: maxRowsPerUser,
      );
    } catch (e, st) {
      logError('Purge pending_locations falló', error: e, stackTrace: st);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Purga puntos huérfanos (de cualquier usuario) con más de 30 días. Cubre el caso de cambio de usuario en el mismo equipo.][obj: PendingLocationRetentionService.purgeOrphaned]
  Future<void> purgeOrphaned({int maxAgeDays = 30}) async {
    try {
      final deleted = await _store.purgeAllOlderThan(Duration(days: maxAgeDays));
      if (deleted > 0) {
        logDebug('Purga de puntos huérfanos: $deleted filas eliminadas (>${maxAgeDays}d)');
      }
    } catch (e, st) {
      logError('Purga de puntos huérfanos falló', error: e, stackTrace: st);
    }
  }
}

