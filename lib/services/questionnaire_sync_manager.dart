// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Línea 3 de sync independiente: respuestas de cuestionarios con disparo inmediato + timer 60s][obj: QuestionnaireSyncManager]
import 'dart:async';

import 'package:get_it/get_it.dart';

import '../utils/logger.dart';
import 'api_service.dart';
import 'offline_questionnaire_store.dart';
import 'telemetry_log_service.dart';

class QuestionnaireSyncManager {
  QuestionnaireSyncManager({
    ApiService? apiService,
    OfflineQuestionnaireStore? questionnaireStore,
  })  : _apiService = apiService ?? ApiService(),
        _questionnaireStore = questionnaireStore ?? OfflineQuestionnaireStore();

  final ApiService _apiService;
  final OfflineQuestionnaireStore _questionnaireStore;

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

  /// Disparo inmediato: llamar al encolar respuestas de cuestionario (DONE).
  void triggerNow() {
    unawaited(syncOnce());
  }

  Future<void> syncOnce() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final pending = await _questionnaireStore.fetchPending();
      if (pending.isEmpty) return;

      for (final record in pending) {
        if (record.attempts > 0) {
          unawaited(GetIt.I<TelemetryLogService>().log(
            'Sync cuestionario: visitId=${record.visitId} reintentando (attempts_previos=${record.attempts})',
          ));
        }
        bool synced = false;
        String? lastError;
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            final respuestas = record.toRespuestas();
            await _apiService.registrarRespuestas(respuestas);
            await _questionnaireStore.markSynced(record.id);
            unawaited(GetIt.I<TelemetryLogService>().log(
              'Sync cuestionario: visitId=${record.visitId} intento=$attempt OK',
            ));
            synced = true;
            break;
          } catch (e) {
            lastError = e.toString();
            final isNetworkError = e is! ApiException;
            if (isNetworkError && attempt < 3) {
              unawaited(GetIt.I<TelemetryLogService>().log(
                'Sync cuestionario: visitId=${record.visitId} intento=$attempt FALLO (red), reintentando 3s',
              ));
              await Future.delayed(const Duration(seconds: 3));
            } else {
              unawaited(GetIt.I<TelemetryLogService>().log(
                'Sync cuestionario: visitId=${record.visitId} intento=$attempt FALLO (${isNetworkError ? "red" : "negocio"}), agotando lote',
              ));
              break;
            }
          }
        }
        if (!synced) {
          await _questionnaireStore.markError(record.id, lastError ?? 'error');
          unawaited(GetIt.I<TelemetryLogService>().log(
            'Sync cuestionario: lote detenido en visitId=${record.visitId}, reintentará próximo ciclo',
          ));
          break;
        }
      }
    } catch (e) {
      logError('Error general en QuestionnaireSyncManager', error: e);
    } finally {
      _syncing = false;
    }
  }
}
