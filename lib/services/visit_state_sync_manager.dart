// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Línea 1 de sync independiente: estados de visita + refresh de plan + refresh de cuestionario en IN_VISIT][obj: VisitStateSyncManager]
import 'dart:async';

import 'package:get_it/get_it.dart';

import '../models/visit_plan.dart';
import '../utils/logger.dart';
import 'api_service.dart';
import 'offline_sync_status.dart';
import 'offline_visit_event_store.dart';
import 'questionnaire_cache_store.dart';
import 'telemetry_log_service.dart';
import 'visit_plan_cache_store.dart';

class VisitStateSyncManager {
  VisitStateSyncManager({
    ApiService? apiService,
    OfflineVisitEventStore? eventStore,
    VisitPlanCacheStore? planCache,
    QuestionnaireCacheStore? questionnaireCache,
    OfflineSyncStatus? status,
  })  : _apiService = apiService ?? ApiService(),
        _eventStore = eventStore ?? OfflineVisitEventStore(),
        _planCache = planCache ?? VisitPlanCacheStore(),
        _questionnaireCache = questionnaireCache ?? QuestionnaireCacheStore(),
        _status = status ?? GetIt.I<OfflineSyncStatus>();

  final ApiService _apiService;
  final OfflineVisitEventStore _eventStore;
  final VisitPlanCacheStore _planCache;
  final QuestionnaireCacheStore _questionnaireCache;
  final OfflineSyncStatus _status;

  Timer? _timer;
  bool _syncing = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => syncOnce());
    syncOnce();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Disparo inmediato: llamar al encolar cualquier estado de visita.
  void triggerNow() {
    unawaited(syncOnce());
  }

  Future<void> syncOnce() async {
    if (_syncing) return;
    _syncing = true;
    final pending = await _eventStore.fetchPending();
    final hadPending = pending.isNotEmpty;
    _status.setSyncing(true, hasPending: hadPending);
    try {
      final ok = await _apiService.checkBackendAvailable();
      _status.setBackendAvailable(ok);
      if (!ok) return;
      await _syncVisitEvents(pending);
      await _refreshPlanCache();
      _status.markCompleted(hadPending: hadPending);
    } catch (e) {
      logWarn('VisitStateSyncManager sync falló', details: e.toString());
      _status.setBackendAvailable(false);
    } finally {
      _syncing = false;
      _status.setSyncing(false);
    }
  }

  Future<void> _syncVisitEvents(List<OfflineVisitEvent> pending) async {
    for (final event in pending) {
      final state = _mapEventType(event.eventType);
      if (state == null) {
        await _eventStore.markError(event.id, 'Estado inválido ${event.eventType}');
        continue;
      }
      if (event.attempts > 0) {
        unawaited(GetIt.I<TelemetryLogService>().log(
          'Sync offline: visitId=${event.visitId} ${event.eventType} reintentando (attempts_previos=${event.attempts})',
        ));
      }
      bool synced = false;
      String? lastError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          await _apiService.updateVisitState(
            itemId: event.visitId,
            newState: state,
            startLatitude: state == VisitItemState.enRoute ? event.latitude : null,
            startLongitude: state == VisitItemState.enRoute ? event.longitude : null,
            eventLatitude: event.latitude,
            eventLongitude: event.longitude,
            occurredAt: DateTime.parse(event.timestamp),
            source: 'offline_sync',
          );
          await _eventStore.markSynced(event.id);
          final coordLog = (state == VisitItemState.enRoute || state == VisitItemState.done)
              ? ' | coords=lat=${event.latitude?.toStringAsFixed(6) ?? "null"} lng=${event.longitude?.toStringAsFixed(6) ?? "null"}'
              : '';
          unawaited(GetIt.I<TelemetryLogService>().log(
            'Sync offline: visitId=${event.visitId} ${event.eventType} intento=$attempt OK$coordLog',
          ));
          synced = true;
          // Al pasar a IN_VISIT, refrescar preguntas del cuestionario
          // para que el usuario las tenga actualizadas antes de responder.
          if (state == VisitItemState.inVisit) {
            await _refreshQuestionnaire();
          }
          break;
        } catch (e) {
          lastError = e.toString();
          final isNetworkError = e is! ApiException;
          if (isNetworkError && attempt < 3) {
            unawaited(GetIt.I<TelemetryLogService>().log(
              'Sync offline: visitId=${event.visitId} ${event.eventType} intento=$attempt FALLO (red), reintentando 3s',
            ));
            await Future.delayed(const Duration(seconds: 3));
          } else {
            unawaited(GetIt.I<TelemetryLogService>().log(
              'Sync offline: visitId=${event.visitId} ${event.eventType} intento=$attempt FALLO (${isNetworkError ? "red" : "negocio"}), agotando lote',
            ));
            break;
          }
        }
      }
      if (!synced) {
        await _eventStore.markError(event.id, lastError ?? 'error');
        unawaited(GetIt.I<TelemetryLogService>().log(
          'Sync offline: lote detenido en ${event.eventType} visitId=${event.visitId}, reintentará próximo ciclo',
        ));
        break;
      }
    }
  }

  Future<void> _refreshQuestionnaire() async {
    try {
      final cuestionario = await _apiService.fetchCuestionarioActivo();
      if (cuestionario != null) {
        final preguntas = await _apiService.fetchPreguntasPorCuestionario(cuestionario.id);
        await _questionnaireCache.save(cuestionario: cuestionario, preguntas: preguntas);
        unawaited(GetIt.I<TelemetryLogService>().log(
          'VisitStateSyncManager: cuestionario refrescado id=${cuestionario.id}',
        ));
      }
    } catch (_) {}
  }

  Future<void> _refreshPlanCache() async {
    try {
      final plan = await _apiService.fetchVisitPlanForMe();
      await _planCache.savePlan(plan);
    } catch (_) {}
  }

  VisitItemState? _mapEventType(String raw) {
    switch (raw) {
      case 'EN_ROUTE':
        return VisitItemState.enRoute;
      case 'ON_SITE':
        return VisitItemState.onSite;
      case 'IN_VISIT':
        return VisitItemState.inVisit;
      case 'DONE':
        return VisitItemState.done;
      default:
        return null;
    }
  }
}
