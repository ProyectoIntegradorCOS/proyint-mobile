// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Refactorizado como coordinador de arranque de las 3 líneas independientes de sync][obj: OfflineSyncManager coordinator]
import 'package:get_it/get_it.dart';

import 'visit_state_sync_manager.dart';
import 'location_sync_manager.dart';
import 'questionnaire_sync_manager.dart';

class OfflineSyncManager {
  OfflineSyncManager({
    VisitStateSyncManager? visitStateSyncManager,
    LocationSyncManager? locationSyncManager,
    QuestionnaireSyncManager? questionnaireSyncManager,
  })  : _visitStateSyncManager = visitStateSyncManager ?? GetIt.I<VisitStateSyncManager>(),
        _locationSyncManager = locationSyncManager ?? GetIt.I<LocationSyncManager>(),
        _questionnaireSyncManager = questionnaireSyncManager ?? GetIt.I<QuestionnaireSyncManager>();

  final VisitStateSyncManager _visitStateSyncManager;
  final LocationSyncManager _locationSyncManager;
  final QuestionnaireSyncManager _questionnaireSyncManager;

  void start() {
    _visitStateSyncManager.start();
    _locationSyncManager.start();
    _questionnaireSyncManager.start();
  }

  void stop() {
    _visitStateSyncManager.stop();
    _locationSyncManager.stop();
    _questionnaireSyncManager.stop();
  }
}

class OfflineSyncBootstrap {
  static void start() {
    GetIt.I<OfflineSyncManager>().start();
  }
}
