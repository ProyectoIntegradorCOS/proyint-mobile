import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/feature_flags.dart';
import '../../../models/visit_plan.dart';
import '../../../services/offline_sync_status.dart';
import '../controllers/history_flow_controller.dart';
import '../controllers/map_screen_controller.dart';
import '../controllers/route_controller.dart';
import '../controllers/tracking_controller.dart';
import '../controllers/visit_controller.dart';
import '../controllers/visit_flow_controller.dart';
import '../map_view_model.dart';
import 'controls_bar.dart';
import 'dwell_overlay.dart';
import 'history_overlay.dart';
import 'map_arrival_panel.dart';
import 'map_floating_buttons.dart';
import 'map_status_panels.dart';
import 'map_visit_panel.dart';
import 'tracking_info_chip.dart';

/// Renders all overlay layers on top of the map base.
/// Accepts controllers, state data, and action callbacks as constructor params
/// so [_MapScreenState] stays thin and this widget can rebuild independently.
class MapOverlayLayer extends StatelessWidget {
  const MapOverlayLayer({
    super.key,
    required this.stateController,
    required this.visitController,
    required this.trackingController,
    required this.routeController,
    required this.visitFlowController,
    required this.viewModel,
    required this.pendingSyncIds,
    required this.pendingQuestionnaireCounts,
    required this.syncStatus,
    required this.trackingWindowLabel,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onOpenLayers,
    required this.onOpenVisitPlan,
    required this.onBootstrap,
    required this.onCenterOnUser,
    required this.onToggleTracking,
    required this.onStartVerification,
    required this.onAdvanceToNextVisit,
    required this.onPromptArrivalConfirmation,
    this.lastKnownAccuracy,
    this.lastKnownSpeed,
    this.lastFixAt,
    this.pendingLocalCount,
    this.lastBgFlushAt,
    this.lastBgFlushStatus,
    this.onRetryConnectionPanel,
    this.onNavigate,
  });

  // Controllers
  final MapScreenController stateController;
  final VisitController visitController;
  final TrackingController trackingController;
  final RouteController routeController;
  final VisitFlowController visitFlowController;

  // ViewModel
  final MapViewModel viewModel;

  // Sync state
  final Set<int> pendingSyncIds;
  final Map<int, int> pendingQuestionnaireCounts;
  final OfflineSyncStatus syncStatus;

  // Tracking label
  final String trackingWindowLabel;

  // Diagnostic fields (nullable / optional)
  final double? lastKnownAccuracy;
  final double? lastKnownSpeed;
  final DateTime? lastFixAt;
  final int? pendingLocalCount;
  final DateTime? lastBgFlushAt;
  final String? lastBgFlushStatus;

  // Action callbacks
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onOpenLayers;
  final VoidCallback onOpenVisitPlan;
  final VoidCallback onBootstrap;
  final VoidCallback onCenterOnUser;
  final VoidCallback onToggleTracking;
  final VoidCallback onStartVerification;
  final VoidCallback onAdvanceToNextVisit;
  final void Function(LatLng, VisitItem?) onPromptArrivalConfirmation;

  // Optional callbacks
  final VoidCallback? onRetryConnectionPanel;
  final VoidCallback? onNavigate;

  // ── Feature flags (mirrors _MapScreenState constants) ───────────────────
  static const double _overlayLeftInset = 72.0;
  static const bool _showTrackingInfo = true;
  static const bool _showStatusBanner = false;
  static const bool _showTrackingControls = false;
  static const bool _showQuickVerificationButton = false;

  HistoryFlowController? get _historyFlowController =>
      GetIt.I.isRegistered<HistoryFlowController>()
          ? GetIt.I<HistoryFlowController>()
          : null;

  // ── Geometry helpers ─────────────────────────────────────────────────────

  bool _isInsideArrivalZoneNow() {
    final target = visitController.currentTarget;
    if (target == null) return false;
    final d = Distance().as(LengthUnit.Meter, stateController.center, target);
    return d <= visitController.arrivalRadiusMeters;
  }

  double? _distanceToTargetMeters() {
    final target = visitController.currentTarget;
    if (target == null) return null;
    return Distance().as(LengthUnit.Meter, stateController.center, target);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          _buildVisitPanel(),
          if (_showTrackingInfo) _buildTrackingInfoChip(context),
          if (stateController.showingHistory &&
              stateController.historyPoints.isNotEmpty)
            _buildHistoryOverlay(context),
          ..._buildArrivalWidgets(context),
          _buildFloatingButtons(),
          if (_showStatusBanner) _buildStatusPanels(),
          if (_showTrackingControls) _buildControlsBar(),
        ],
      ),
    );
  }

  // ── Sub-builders ─────────────────────────────────────────────────────────

  // Panel superior de visita y estado
  Widget _buildVisitPanel() {
    final currentVisit = viewModel.currentVisit;
    final hasVisits = viewModel.totalVisitsCount > 0;
    final pendingCount = viewModel.pendingVisitsCount;
    final completedCount = viewModel.completedVisitsCount;
    final totalCount = viewModel.totalVisitsCount;
    final currentVisitId = int.tryParse(currentVisit?.id ?? '');
    final pendingSync =
        currentVisitId != null && pendingSyncIds.contains(currentVisitId);
    final pendingQuestionnaireCount = currentVisitId != null
        ? (pendingQuestionnaireCounts[currentVisitId] ?? 0)
        : 0;
    final pendingQuestionnaire = pendingQuestionnaireCount > 0;
    final syncing = syncStatus.syncing && syncStatus.hasPending;
    return Positioned(
      top: 16,
      left: _overlayLeftInset,
      right: 16,
      child: MapVisitPanel(
        trackingStatus: stateController.trackingStatus,
        showTrackingStatus: _showStatusBanner,
        showTrackingInfo: false,
        showEmptyVisit: hasVisits && pendingCount > 0,
        pendingCount: pendingCount,
        totalCount: totalCount,
        completedCount: completedCount,
        pendingSync: pendingSync,
        syncing: syncing,
        pendingQuestionnaire: pendingQuestionnaire,
        pendingQuestionnaireCount: pendingQuestionnaireCount,
        connectionMessage: stateController.connectionMessage,
        onRetryConnection: onRetryConnectionPanel,
        currentVisit: currentVisit,
        onCheckIn: onStartVerification,
        onCheckOut: onAdvanceToNextVisit,
        onValidate: onStartVerification,
        accuracy: stateController.lastKnownAccuracy,
        speed: stateController.lastKnownSpeed,
        lastFix: stateController.lastFixAt,
        scheduleLabel: trackingWindowLabel,
        filterDecision: trackingController.lastFilterDecision,
      ),
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:57 UTC-5 (Lima)][desc: Mueve chip de tracking a pie de pantalla con ancho máximo adaptable][obj: MapOverlayLayer tracking info footer]
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:02 UTC-5 (Lima)][desc: Ajusta ancho y posición del chip para evitar superposición con controles del mapa][obj: MapOverlayLayer tracking info footer spacing]
  Widget _buildTrackingInfoChip(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 50,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(
                MediaQuery.of(context).size.width - 32,
                260,
              ),
            ),
            child: TrackingInfoChip(
              accuracy: stateController.lastKnownAccuracy ?? lastKnownAccuracy,
              speed: stateController.lastKnownSpeed ?? lastKnownSpeed,
              lastFix: stateController.lastFixAt ?? lastFixAt,
              scheduleLabel: trackingWindowLabel,
              filterDecision: trackingController.lastFilterDecision,
              pendingLocalCount: pendingLocalCount,
              lastSyncOkAt: syncStatus.lastCompletedAt,
              backendAvailable: syncStatus.backendAvailable,
              bgFlushAt: lastBgFlushAt,
              bgFlushStatus: lastBgFlushStatus,
            ),
          ),
        ),
      ),
    );
  }

  // Overlay de historial
  Widget _buildHistoryOverlay(BuildContext context) {
    return Positioned(
      top: 16,
      left: _overlayLeftInset,
      right: 16,
      child: HistoryOverlay(
        routeLength: stateController.historyPoints.length,
        lastDistanceKm: stateController.totalDistanceKm,
        lastHistoryRange: stateController.lastHistoryRange,
        onShowDetails: () {
          _historyFlowController?.showHistoryDetails(context);
        },
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Permite cerrar overlay de historial y limpiar estado][obj: MapOverlayLayer close history overlay]
        onClose: () {
          stateController.setShowingHistory(false);
          stateController.resetHistory();
        },
      ),
    );
  }

  List<Widget> _buildArrivalWidgets(BuildContext context) {
    return [
      if (visitController.currentTarget != null ||
          visitController.activePlanVisit?.state == VisitItemState.inVisit)
        MapArrivalPanel(
          distanceText:
              _distanceToTargetMeters()?.toStringAsFixed(0) ?? '--',
          isInsideArrivalZone: _isInsideArrivalZoneNow(),
          arrivalConfirmed: visitController.arrivalConfirmed,
          activePlanVisit: visitController.activePlanVisit,
          showingHistory: stateController.showingHistory,
          onConfirmArrival: () => onPromptArrivalConfirmation(
              stateController.center, visitController.activePlanVisit),
          onStartVisit: () => visitFlowController.startPlanVisitNow(context),
          onCompleteVisit: onStartVerification,
        ),
      if (visitController.activePlanVisit?.state == VisitItemState.inVisit)
        Positioned(
          top: stateController.showingHistory ? 140 : 76,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onStartVerification,
              child: const Text(
                'Completar visita',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
      // Overlay de espera en destino
      if (visitController.dwellInProgress &&
          visitController.dwellEndsAt != null)
        Positioned(
          bottom: 20,
          left: 16,
          right: 16,
          child: DwellOverlay(
            dwellEndsAt: visitController.dwellEndsAt!,
            arrivalRadius: visitController.arrivalRadiusMeters,
            onStartVerification: onStartVerification,
          ),
        ),
    ];
  }

  // Botones flotantes
  Widget _buildFloatingButtons() {
    final moveLayerButtonDown = viewModel.pendingVisitsCount > 0;
    return MapFloatingButtons(
      mapReady: stateController.mapReady,
      showingHistory: stateController.showingHistory,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Usa ruta activa del RouteController (no variable local restaurada) para habilitar navegación][obj: MapOverlayLayer routeActive]
      routeActive: routeController.activeRoute != null,
      dwellInProgress: visitController.dwellInProgress,
      showQuickVerification: _showQuickVerificationButton,
      isInsideArrivalZone: _isInsideArrivalZoneNow(),
      arrivalConfirmed: visitController.arrivalConfirmed,
      moveLayersDown: moveLayerButtonDown,
      onLayers: onOpenLayers,
      onZoomIn: onZoomIn,
      onZoomOut: onZoomOut,
      onVisitPlan: onOpenVisitPlan,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 17:15 UTC-5 (Lima)][desc: Habilita navegación nativa solo con feature-flag (producción mantiene mapa actual)][obj: MapOverlayLayer onNavigate feature flag]
      onNavigate: FeatureFlags.enableNativeNavigation ? onNavigate : null,
      onQuickVerification: () {
        if (_isInsideArrivalZoneNow() && !visitController.arrivalConfirmed) {
          onPromptArrivalConfirmation(
              stateController.center, visitController.activePlanVisit);
        } else {
          onStartVerification();
        }
      },
    );
  }

  // Paneles de estado y overlays
  Widget _buildStatusPanels() {
    return MapStatusPanels(
      waitingInitialFix: trackingController.waitingInitialFix,
      shutdownMessage: stateController.shutdownMessage,
      connectionMessage: stateController.connectionMessage,
      onRetryConnection: () {
        stateController.setIsLoading(true);
        stateController.setConnectionMessage(null);
        onBootstrap();
      },
    );
  }

  Widget _buildControlsBar() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 12,
      child: SafeArea(
        child: ControlsBar(
          isTracking: trackingController.isTracking,
          filtersActive: stateController.showingHistory,
          onToggleTracking: onToggleTracking,
          onCenterOnUser: onCenterOnUser,
          onToggleFilters: () {
            final next = !stateController.showingHistory;
            stateController.setShowingHistory(next);
          },
        ),
      ),
    );
  }
}
