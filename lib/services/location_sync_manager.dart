// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Línea 2 independiente: timer 10s si hay pendientes + fallback 60s + flushNativePendingNow movido aquí][obj: LocationSyncManager timers]
import 'dart:async';

import 'package:get_it/get_it.dart';
import '../models/location_point.dart';
import '../models/pending_location.dart';
import '../utils/logger.dart';
import '../utils/lima_time.dart';
import 'api_service.dart';
import 'background_schedule_manager.dart';
import 'auth_service.dart';
import 'pending_location_store.dart';
import 'pending_location_retention_service.dart';
import 'telemetry_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationSyncManager {
  static const int _batchSize = 10;
  static const int _retentionDays = 15;
  static const int _maxRowsPerUser = 5000;

  LocationSyncManager({
    ApiService? apiService,
    PendingLocationStore? store,
  })  : _apiService = apiService ?? ApiService(),
        _store = store ?? PendingLocationStore();

  final ApiService _apiService;
  final PendingLocationStore _store;

  Timer? _shortTimer;
  Timer? _fallbackTimer;

  /// Inicia los timers independientes de ubicación.
  void start() {
    _shortTimer?.cancel();
    _fallbackTimer?.cancel();
    // Cada 10s: flush si hay pendientes
    _shortTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final uid = await _resolveUid();
      if (uid == null || uid.isEmpty) return;
      final count = await _store.countForSubject(uid);
      if (count > 0) await flushPending(firebaseUid: uid);
    });
    // Cada 60s: fallback para vaciar rezagos
    _fallbackTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      final uid = await _resolveUid();
      if (uid == null || uid.isEmpty) return;
      await flushPending(firebaseUid: uid);
      try {
        final nativeResult = await BackgroundScheduleManager.flushNativePendingNow();
        GetIt.I<TelemetryLogService>().log('LocationSyncManager: flush nativo → $nativeResult');
      } catch (_) {}
    });
  }

  void stop() {
    _shortTimer?.cancel();
    _fallbackTimer?.cancel();
    _shortTimer = null;
    _fallbackTimer = null;
  }

  Future<String?> _resolveUid() async {
    final session = GetIt.I<AuthService>().currentSession;
    if (session != null && (session.uid.isNotEmpty)) return session.uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_uid');
    } catch (_) {
      return null;
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Encola ubicación y verifica si debe enviar lote][obj: LocationSyncManager.queueLocation]
  /// Guarda la ubicación localmente y verifica si debe enviar el lote.
  Future<void> queueLocation({
    required String firebaseUid,
    required LocationPoint point,
    int? batteryLevel,
    String? activityType,
  }) async {
    logDebug('Encolando ubicación',
        details: 'uid=$firebaseUid lat=${point.latitude} lng=${point.longitude}');
    
    final pending = PendingLocation(
      saaSubject: firebaseUid,
      latitude: point.latitude,
      longitude: point.longitude,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Timestamp se encola en formato Lima (-05:00) y epoch para retención/purga][obj: LocationSyncManager.queueLocation timestamp Lima]
      timestamp: toLimaIsoString(point.timestamp),
      timestampEpochMs: point.timestamp.toUtc().millisecondsSinceEpoch,
      accuracy: point.accuracy ?? 0.0,
      altitude: point.altitude ?? 0.0,
      speed: point.speed ?? 0.0,
      heading: point.heading ?? 0.0,
      batteryLevel: (batteryLevel ?? 0).toDouble(),
      activityType: activityType ?? 'unknown',
    );

    await _store.insert(pending);

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Conteo por usuario para no mezclar colas en el batching][obj: LocationSyncManager.queueLocation countForSubject]
    final count = await _store.countForSubject(firebaseUid);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Telemetría de captura Flutter: lat/lng + estado SQLite][obj: LocationSyncManager.queueLocation telemetry]
    try {
      GetIt.I<TelemetryLogService>().log(
        'Punto Flutter → SQLite: lat=${point.latitude.toStringAsFixed(6)} lng=${point.longitude.toStringAsFixed(6)} pendientes=$count',
      );
    } catch (_) {}
    if (count >= _batchSize) {
      await flushPending(firebaseUid: firebaseUid);
    }
  }

  /// Intenta enviar las ubicaciones pendientes en lotes.
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Flush por usuario para evitar enviar ubicaciones de otro login con token actual][obj: LocationSyncManager.flushPending]
  Future<void> flushPending({required String firebaseUid}) async {
    try {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Aplica retención/purga antes de sincronizar pendientes][obj: LocationSyncManager.flushPending retention]
      await PendingLocationRetentionService(
        store: _store,
        maxAgeDays: _retentionDays,
        maxRowsPerUser: _maxRowsPerUser,
      ).purgeForUser(firebaseUid);

      final count = await _store.countForSubject(firebaseUid);
      if (count == 0) {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Traza cuando no hay pendientes por usuario (útil para diagnosticar cola nativa vs Flutter)][obj: LocationSyncManager.flushPending empty trace]
        final total = await _store.count();
        final peek = await _store.peekOldest();
        logDebug(
          'Sin ubicaciones pendientes para flush',
          details:
              'uid=$firebaseUid totalAll=$total oldest=${peek ?? "-"}',
        );
        return;
      }

      logDebug(
        'Iniciando sincronización de $count ubicaciones pendientes',
        details: 'uid=$firebaseUid',
      );

      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Traza min/max timestamps en cola para confirmar envío de periodo deslogueado][obj: LocationSyncManager.flushPending minmax]
      try {
        final minMax = await _store.getMinMaxTimestampsForSubject(firebaseUid);
        if (minMax != null) {
          logDebug(
            'Pending queue snapshot',
            details:
                'uid=$firebaseUid count=$count minTs=${minMax.$1} maxTs=${minMax.$2}',
          );
        }
      } catch (_) {}

      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Telemetría de flush: log inicio con total pendientes][obj: LocationSyncManager.flushPending telemetry]
      try {
        GetIt.I<TelemetryLogService>().log(
          'Flush Flutter SQLite → backend: iniciando uid=$firebaseUid total=$count',
        );
      } catch (_) {}

      // Procesamos en lotes
      int totalEnviados = 0;
      while (true) {
        final batch = await _store.getBatchForSubject(firebaseUid, _batchSize);
        if (batch.isEmpty) break;

        try {
          // Convertimos a mapa para el API
          final List<Map<String, dynamic>> payload = batch.map((e) => e.toMap()).toList();

          await _apiService.sendLocationBatch(payload);

          // Si se envió correctamente, borramos del store
          final ids = batch.map((e) => e.id!).toList();
          await _store.deleteBatch(ids);
          totalEnviados += batch.length;

          logDebug('Lote de ${batch.length} enviado y eliminado localmente');
        } catch (e) {
          logError('Error enviando lote', error: e);
          // Si falla un lote, detenemos el proceso para reintentar luego
          // (presumiblemente error de red)
          break;
        }
      }
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Telemetría de flush: log resultado con enviados y pendientes restantes][obj: LocationSyncManager.flushPending telemetry result]
      try {
        final remaining = await _store.countForSubject(firebaseUid);
        GetIt.I<TelemetryLogService>().log(
          'Flush Flutter SQLite → backend: enviados=$totalEnviados restantes=$remaining uid=$firebaseUid',
        );
      } catch (_) {}
    } catch (e) {
      logError('Error general en flushPending', error: e);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:30 UTC-5 (Lima)][desc: Obtiene puntos pendientes (local DB) para pintar ruta en otro color][obj: LocationSyncManager.getPendingPointsForSubject]
  Future<List<LocationPoint>> getPendingPointsForSubject(String firebaseUid) async {
    final rows = await _store.getAllForSubject(firebaseUid);
    return rows.map((p) {
      final ts =
          DateTime.tryParse(p.timestamp) ??
          DateTime.fromMillisecondsSinceEpoch(
            p.timestampEpochMs ?? 0,
            isUtc: true,
          );
      return LocationPoint(
        latitude: p.latitude,
        longitude: p.longitude,
        timestamp: ts,
        accuracy: p.accuracy,
        altitude: p.altitude,
        speed: p.speed,
        heading: p.heading,
      );
    }).toList();
  }
}
