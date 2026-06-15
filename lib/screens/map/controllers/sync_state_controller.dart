import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/offline_questionnaire_store.dart';
import '../../../services/offline_sync_status.dart';
import '../../../services/offline_visit_event_store.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 18:12 UTC-5 (Lima)][desc: Extrae del State la lectura de sync offline, flush nativo y control del último toast de sincronización][obj: SyncStateController]
class SyncStateController {
  SyncStateController({
    OfflineVisitEventStore? offlineEventStore,
    OfflineQuestionnaireStore? offlineQuestionnaireStore,
  })  : _offlineEventStore = offlineEventStore ?? OfflineVisitEventStore(),
        _offlineQuestionnaireStore =
            offlineQuestionnaireStore ?? OfflineQuestionnaireStore();

  final OfflineVisitEventStore _offlineEventStore;
  final OfflineQuestionnaireStore _offlineQuestionnaireStore;

  Set<int> pendingSyncIds = const {};
  Map<int, int> pendingQuestionnaireCounts = const {};
  DateTime? lastBgFlushAt;
  String? lastBgFlushStatus;
  DateTime? _lastSyncToastAt;

  Future<void> refreshPendingSyncIds() async {
    final pending = await _offlineEventStore.fetchPendingVisitIds();
    final questionnaires =
        await _offlineQuestionnaireStore.fetchPendingCountsByVisit();
    pendingSyncIds = pending;
    pendingQuestionnaireCounts = questionnaires;
  }

  Future<void> loadBgFlushInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAtRaw = prefs.getString('bg_flush_last_at');
    final status = prefs.getString('bg_flush_last_status');
    lastBgFlushAt = lastAtRaw == null ? null : DateTime.tryParse(lastAtRaw);
    lastBgFlushStatus = status;
  }

  bool shouldShowSyncCompletedToast(OfflineSyncStatus status) {
    final completedAt = status.lastCompletedAt;
    if (completedAt == null || !status.lastHadPending) return false;
    if (_lastSyncToastAt != null && !completedAt.isAfter(_lastSyncToastAt!)) {
      return false;
    }
    _lastSyncToastAt = completedAt;
    return true;
  }
}
