import 'package:flutter/material.dart';
import '../../../../models/assigned_visit.dart';
import 'status_banner.dart';
import 'visit_panel.dart';
import 'tracking_info_chip.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 14:45 UTC-5 (Lima)][desc: Widget para panel superior de visita y estado][obj: MapVisitPanel]
class MapVisitPanel extends StatelessWidget {
  final TrackingStatus trackingStatus;
  final String? connectionMessage;
  final VoidCallback? onRetryConnection;
  final AssignedVisit? currentVisit;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback onValidate;
  final double? accuracy;
  final double? speed;
  final DateTime? lastFix;
  final String? scheduleLabel;
  final String? filterDecision;
  final int? pendingLocalCount;
  final DateTime? lastSyncOkAt;
  final bool? backendAvailable;
  final DateTime? bgFlushAt;
  final String? bgFlushStatus;
  final bool showTrackingStatus;
  final bool showTrackingInfo;
  final bool showEmptyVisit;
  final int pendingCount;
  final int totalCount;
  final int completedCount;
  final bool pendingSync;
  final bool syncing;
  final bool pendingQuestionnaire;
  final int pendingQuestionnaireCount;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-12 10:55 UTC-5 (Lima)][desc: Propaga contadores para mensaje dinámico de visitas pendientes][obj: MapVisitPanel props]
  const MapVisitPanel({
    super.key,
    required this.trackingStatus,
    this.connectionMessage,
    this.onRetryConnection,
    this.currentVisit,
    required this.onCheckIn,
    required this.onCheckOut,
    required this.onValidate,
    this.accuracy,
    this.speed,
    this.lastFix,
    this.scheduleLabel,
    this.filterDecision,
    this.pendingLocalCount,
    this.lastSyncOkAt,
    this.backendAvailable,
    this.bgFlushAt,
    this.bgFlushStatus,
    this.showTrackingStatus = true,
    this.showTrackingInfo = false,
    this.showEmptyVisit = true,
    this.pendingCount = 0,
    this.totalCount = 0,
    this.completedCount = 0,
    this.pendingSync = false,
    this.syncing = false,
    this.pendingQuestionnaire = false,
    this.pendingQuestionnaireCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Banner de estado opcional][obj: MapVisitPanel]
          if (showTrackingStatus) ...[
            StatusBanner(
              status: trackingStatus,
              message: connectionMessage,
              onRetry: onRetryConnection,
            ),
            const SizedBox(height: 8),
          ],
          VisitPanel(
            visit: currentVisit,
            onCheckIn: onCheckIn,
            onCheckOut: onCheckOut,
            onValidate: onValidate,
            showEmpty: showEmptyVisit,
            pendingCount: pendingCount,
            totalCount: totalCount,
            completedCount: completedCount,
            pendingSync: pendingSync,
            syncing: syncing,
            pendingQuestionnaire: pendingQuestionnaire,
            pendingQuestionnaireCount: pendingQuestionnaireCount,
          ),
          if (showTrackingInfo) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TrackingInfoChip(
                accuracy: accuracy,
                speed: speed,
                lastFix: lastFix,
                scheduleLabel: scheduleLabel,
                filterDecision: filterDecision,
                pendingLocalCount: pendingLocalCount,
                lastSyncOkAt: lastSyncOkAt,
                backendAvailable: backendAvailable,
                bgFlushAt: bgFlushAt,
                bgFlushStatus: bgFlushStatus,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
