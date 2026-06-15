import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/models/visit_plan.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../models/assigned_visit.dart';
import '../../../../utils/logger.dart';

//import '../../../../services/mock_schedule_service.dart';
//import '../../../../services/auth_service.dart';

import '../../../../services/api_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/visit_plan_cache_store.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:05 UTC-5 (Lima)][desc: Crea controlador especializado para lógica de visitas][obj: VisitController]
class VisitController extends ChangeNotifier {
  VisitController({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  final ApiService _apiService;
  final VisitPlanCacheStore _planCache = VisitPlanCacheStore();
  List<VisitItem> _todayPlanItems = const [];
  List<AssignedVisit> _todayVisits = const [];
  int _currentVisitIndex = -1;
  final Set<String> _completedVisitIds = <String>{};
  bool _verificationInProgress = false;

  // Arrival detection state
  LatLng? _currentTarget;
  double _arrivalRadiusMeters = 50.0;
  Duration _dwellDuration = const Duration(minutes: 5);
  bool _arrivalConfirmed = false;
  bool _wasInsideArrivalZone = false;
  bool _dwellInProgress = false;
  DateTime? _dwellEndsAt;
  LatLng? _arrivalRefPoint;
  Timer? _dwellTimer;
  Timer? _dwellTick;
  Timer? _visitReminderTimer;
  int _visitReminderMinutes = 20;
  
  // Smart Alerts
  Timer? _smartAlertTimer;
  DateTime? _lastSmartAlertCheck;
  Function(VisitItem, DateTime)? onSmartAlert;


  List<AssignedVisit> get todayVisits => _todayVisits;
  List<VisitItem> get todayPlanItems => _todayPlanItems;
  int get currentVisitIndex => _currentVisitIndex;
  Set<String> get completedVisitIds => _completedVisitIds;
  bool get verificationInProgress => _verificationInProgress;
  LatLng? get currentTarget => _currentTarget;
  double get arrivalRadiusMeters => _arrivalRadiusMeters;
  Duration get dwellDuration => _dwellDuration;
  bool get arrivalConfirmed => _arrivalConfirmed;
  bool get wasInsideArrivalZone => _wasInsideArrivalZone;
  bool get dwellInProgress => _dwellInProgress;
  DateTime? get dwellEndsAt => _dwellEndsAt;
  LatLng? get arrivalRefPoint => _arrivalRefPoint;
  int get visitReminderMinutes => _visitReminderMinutes;

  AssignedVisit? get currentVisit {
    if (_currentVisitIndex >= 0 && _currentVisitIndex < _todayVisits.length) {
      return _todayVisits[_currentVisitIndex];
    }
    return null;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:07 UTC-5 (Lima)][desc: Establece lista de visitas del día][obj: VisitController.setVisits]
  void setVisits(List<AssignedVisit> visits, {int? currentIndex}) {
    _todayVisits = visits;
    _currentVisitIndex = currentIndex ?? _currentVisitIndex;
    logDebug(
      'Visitas seteadas',
      details: 'total=${_todayVisits.length} completadas=${_completedVisitIds.length}',
    );
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:07 UTC-5 (Lima)][desc: Marca visita como completada][obj: VisitController.markVisitCompleted]
  void markVisitCompleted(int index) {
    if (index >= 0 && index < _todayVisits.length) {
      _completedVisitIds.add(_todayVisits[index].id);
      logDebug(
        'Visita completada',
        details:
            'id=${_todayVisits[index].id} pendientes=${_todayVisits.length - _completedVisitIds.length}',
      );
      notifyListeners();
    }
  }

  void markVisitCompletedById(String id) {
    _completedVisitIds.add(id);
    logDebug(
      'Visita completada por id',
      details:
          'id=$id pendientes=${_todayVisits.length - _completedVisitIds.length}',
    );
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:08 UTC-5 (Lima)][desc: Establece índice de visita actual][obj: VisitController.setCurrentVisitIndex]
  void setCurrentVisitIndex(int index) {
    if (index >= 0 && index < _todayVisits.length) {
      _currentVisitIndex = index;
      notifyListeners();
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:08 UTC-5 (Lima)][desc: Avanza a la siguiente visita][obj: VisitController.advanceToNext]
  bool advanceToNext() {
    if (_currentVisitIndex < _todayVisits.length - 1) {
      _currentVisitIndex++;
      notifyListeners();
      return true;
    }
    return false;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:09 UTC-5 (Lima)][desc: Establece destino actual para arrival detection][obj: VisitController.setCurrentTarget]
  void setCurrentTarget(LatLng? target) {
    _currentTarget = target;
    _persistArrivalTarget(target);
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:09 UTC-5 (Lima)][desc: Configura parámetros de arrival detection][obj: VisitController.configureArrivalDetection]
  void configureArrivalDetection({
    double? radiusMeters,
    Duration? dwellDuration,
  }) {
    if (radiusMeters != null) _arrivalRadiusMeters = radiusMeters;
    if (dwellDuration != null) _dwellDuration = dwellDuration;
    if (radiusMeters != null) {
      _persistArrivalRadius(radiusMeters);
    }
    notifyListeners();
  }

  void _persistArrivalTarget(LatLng? target) {
    // Persist for native tracking alerts (background).
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (target == null) {
          await prefs.setBool('arrival_target_enabled', false);
          return;
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Resetea contador de alertas al asignar nuevo destino para que el nativo pueda disparar las 2 alertas del nuevo target][obj: VisitController._persistArrivalTarget reset alert count]
        await prefs.setInt('arrival_alert_count', 0);
        await prefs.setBool('arrival_target_enabled', true);
        await prefs.setString('arrival_target_lat', target.latitude.toString());
        await prefs.setString('arrival_target_lng', target.longitude.toString());
        await prefs.setString('arrival_target_radius_m', _arrivalRadiusMeters.toString());
      } catch (_) {}
    }();
  }

  void _persistArrivalRadius(double radiusMeters) {
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('arrival_target_radius_m', radiusMeters.toString());
      } catch (_) {}
    }();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:10 UTC-5 (Lima)][desc: Inicia monitoreo de dwell][obj: VisitController.startDwellMonitoring]
  void startDwellMonitoring(LatLng referencePoint) {
    _dwellTimer?.cancel();
    _dwellTick?.cancel();
    _dwellInProgress = true;
    _dwellEndsAt = DateTime.now().add(_dwellDuration);
    _arrivalRefPoint = referencePoint;
    _dwellTimer = Timer(_dwellDuration, _onDwellComplete);
    _dwellTick = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:10 UTC-5 (Lima)][desc: Cancela monitoreo de dwell][obj: VisitController.cancelDwellMonitoring]
  void cancelDwellMonitoring() {
    _dwellTimer?.cancel();
    _dwellTick?.cancel();
    _dwellInProgress = false;
    _dwellEndsAt = null;
    _arrivalRefPoint = null;
    _wasInsideArrivalZone = false;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:11 UTC-5 (Lima)][desc: Confirma llegada a destino][obj: VisitController.confirmArrival]
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Deshabilita alerta nativa al confirmar llegada para que el servicio Android deje de vibrar/sonar][obj: VisitController.confirmArrival disable native]
  void confirmArrival() {
    _arrivalConfirmed = true;
    cancelDwellMonitoring();
    _persistArrivalTarget(null); // Deshabilita alertas nativas para este destino
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:11 UTC-5 (Lima)][desc: Actualiza estado de zona de llegada][obj: VisitController.updateArrivalZoneState]
  void updateArrivalZoneState(bool isInside) {
    _wasInsideArrivalZone = isInside;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-26 00:00 UTC-5 (Lima)][desc: Limpia flag de "ya estuvo dentro" al reiniciar sesión para permitir re-disparo del modal][obj: VisitController.resetArrivalZoneFlag]
  void resetArrivalZoneFlag() {
    _wasInsideArrivalZone = false;
    notifyListeners();
  }

  void setArrivalRefPoint(LatLng? point) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 17:05 UTC (Lima)][desc: Ajusta punto de referencia de llegada][obj: VisitController.setArrivalRefPoint]
    _arrivalRefPoint = point;
    notifyListeners();
  }

  void resetArrivalState({LatLng? target}) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 17:05 UTC (Lima)][desc: Resetea estado de llegada/dwell][obj: VisitController.resetArrivalState]
    _dwellTimer?.cancel();
    _dwellTick?.cancel();
    _arrivalConfirmed = false;
    _wasInsideArrivalZone = false;
    _currentTarget = target;
    _dwellInProgress = false;
    _dwellEndsAt = null;
    _arrivalRefPoint = null;
    notifyListeners();
  }

  VisitItem? _activePlanVisit;
  DateTime? _activeVisitStartedAt;

  VisitItem? get activePlanVisit => _activePlanVisit;
  DateTime? get activeVisitStartedAt => _activeVisitStartedAt;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-07 09:26 UTC-5 (Lima)][desc: Permite fijar visita activa del plan sin iniciar recordatorio][obj: VisitController.setActivePlanVisit]
  void setActivePlanVisit(VisitItem? visit) {
    _activePlanVisit = visit;
    _activeVisitStartedAt = null;
    notifyListeners();
  }

  void startVisitReminder({
    required int minutes,
    required VoidCallback onReminder,
    VisitItem? visit,
    DateTime? startTime,
  }) {
    _activePlanVisit = visit;
    _activeVisitStartedAt = startTime ?? DateTime.now();
    _visitReminderTimer?.cancel();
    _visitReminderMinutes = minutes;
    _visitReminderTimer = Timer.periodic(
      Duration(minutes: _visitReminderMinutes),
      (_) => onReminder(),
    );
    notifyListeners();
  }

  void stopVisitReminder() {
    _visitReminderTimer?.cancel();
    _visitReminderTimer = null;
    _activePlanVisit = null;
    _activeVisitStartedAt = null;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:11 UTC-5 (Lima)][desc: Establece estado de verificación][obj: VisitController.setVerificationInProgress]
  void setVerificationInProgress(bool value) {
    _verificationInProgress = value;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:12 UTC-5 (Lima)][desc: Resetea estado de visitas][obj: VisitController.reset]
  void reset() {
    _dwellTimer?.cancel();
    _dwellTick?.cancel();
    _todayVisits = const [];
    _currentVisitIndex = -1;
    _completedVisitIds.clear();
    _verificationInProgress = false;
    _currentTarget = null;
    _arrivalConfirmed = false;
    _dwellInProgress = false;
    _dwellEndsAt = null;
    _arrivalRefPoint = null;
    _wasInsideArrivalZone = false;
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:12 UTC-5 (Lima)][desc: Verifica si una ubicación está dentro del radio de llegada][obj: VisitController.isWithinArrivalRadius]
  bool isWithinArrivalRadius(LatLng currentLocation) {
    if (_currentTarget == null) return false;

    final distance = const Distance().distance(
      _currentTarget!,
      currentLocation,
    );

    return distance <= _arrivalRadiusMeters;
  }

  void _onDwellComplete() {
    _dwellTick?.cancel();
    _dwellInProgress = false;
    notifyListeners();
  }

  /* [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:20 UTC-5 (Lima)][desc: Carga visitas, aplica orden guardado y notifica][obj: VisitController.loadVisits]
  Future<void> loadVisits() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    var visits = await MockScheduleService().fetchTodayVisits();
    visits = await _applySavedOrder(session.uid, visits);

    _todayVisits = visits;
    _currentVisitIndex = 0; // Default to first
    notifyListeners();
  }*/

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Carga visitas reales via ApiService y aplica orden guardado][obj: VisitController.loadVisits]
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: Valida que el plan sea del día actual (Lima UTC-5) antes de aplicarlo; si es de otro día limpia la lista para no mostrar visitas de días anteriores en el banner][obj: VisitController.loadVisits date guard]
  Future<void> loadVisits() async {
    logDebug('VisitController.loadVisits start');
    final session = GetIt.I<AuthService>().currentSession;
    if (session == null) {
      logWarn('VisitController.loadVisits sin sesión activa');
      return;
    }

    _completedVisitIds.clear();

    void clearVisits() {
      _todayVisits = const [];
      _todayPlanItems = const [];
      _currentVisitIndex = -1;
      _completedVisitIds.clear();
      notifyListeners();
    }

    try {
      logDebug('VisitController.loadVisits fetching plan');
      final backendOk = await _apiService.checkBackendAvailable(
        timeout: const Duration(seconds: 3),
      );
      if (!backendOk) {
        throw Exception('Backend no disponible');
      }
      final plan = await _apiService.fetchVisitPlanForMe();
      logDebug('VisitController.loadVisits plan recibido',
          details: 'id=${plan.id} items=${plan.items.length} plannedFor=${plan.plannedFor}');
      if (!_isTodayLima(plan.plannedFor)) {
        logWarn('VisitController.loadVisits plan no es de hoy, limpiando visitas',
            details: 'plannedFor=${plan.plannedFor}');
        clearVisits();
        return;
      }
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Aplica el plan a la UI antes de guardarlo en caché, así si savePlan falla por cualquier motivo (ej: migración de BD pendiente) el plan igual se muestra][obj: VisitController.loadVisits order fix]
      await _applyPlan(session.uid, plan);
      notifyListeners();
      await _planCache.savePlan(plan);
    } catch (e) {
      logWarn('VisitController.loadVisits fallback cache', details: e.toString());
      final cached = await _planCache.loadLatest();
      if (cached != null && _isTodayLima(cached.plannedFor)) {
        await _applyPlan(session.uid, cached);
        notifyListeners();
      } else {
        logError('No se pudieron cargar visitas desde el backend', error: e);
        clearVisits();
      }
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: Verifica si la fecha del plan corresponde al día actual en hora de Lima (UTC-5)][obj: VisitController._isTodayLima]
  static bool _isTodayLima(DateTime? plannedFor) {
    if (plannedFor == null) return false;
    final nowLima = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final planLima = plannedFor.toUtc().subtract(const Duration(hours: 5));
    return nowLima.year == planLima.year &&
        nowLima.month == planLima.month &&
        nowLima.day == planLima.day;
  }

  Future<void> _applyPlan(String uid, VisitPlan plan) async {
    _todayPlanItems = plan.items;
    final mapped = plan.items.map((item) {
      final lat = item.latitude ?? 0.0;
      final lng = item.longitude ?? 0.0;
      logDebug('VisitController.map item',
          details:
              'id=${item.id} name=${item.companyName} state=${item.state} lat=$lat lng=$lng');
      return AssignedVisit(
        id: item.id.toString(),
        name: item.companyName,
        address: item.address,
        latitude: lat,
        longitude: lng,
        confirmed: item.state == VisitItemState.done,
        scheduledAt: item.targetTime,
        toleranceMinutes: 10,
      );
    }).toList();

    final ordered = await _applySavedOrder(uid, mapped);
    _todayVisits = ordered;
    logDebug('VisitController.loadVisits ordenadas',
        details:
            'total=${ordered.length} completedFlags=${ordered.where((v) => v.confirmed).length}');
    for (final v in ordered) {
      if (v.confirmed) {
        _completedVisitIds.add(v.id);
      }
    }
    _currentVisitIndex = -1;
  }

  void updatePlanItemState(int itemId, VisitItemState newState) {
    _todayPlanItems = _todayPlanItems
        .map((item) => item.id == itemId ? item.copyWith(state: newState) : item)
        .toList();
    if (_activePlanVisit?.id == itemId) {
      _activePlanVisit = _activePlanVisit?.copyWith(state: newState);
    }
    notifyListeners();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:20 UTC-5 (Lima)][desc: Aplica orden guardado en SharedPreferences][obj: VisitController._applySavedOrder]
  Future<List<AssignedVisit>> _applySavedOrder(
    String uid,
    List<AssignedVisit> visits,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'visit_order_$uid';
    final saved = prefs.getStringList(key);
    if (saved == null || saved.isEmpty) return visits;

    final byId = {for (final v in visits) v.id: v};
    final reordered = <AssignedVisit>[];
    for (final id in saved) {
      final v = byId.remove(id);
      if (v != null) reordered.add(v);
    }
    // Append any new or missing visits at the end
    reordered.addAll(byId.values);
    return reordered;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:22 UTC-5 (Lima)][desc: Selecciona la siguiente visita pendiente más cercana][obj: VisitController.selectNextVisit]
  void selectNextVisit(LatLng currentPosition) {
    if (_todayVisits.isEmpty) return;

    int? bestIndex;
    double minDistance = double.infinity;
    const distance = Distance();

    for (int i = 0; i < _todayVisits.length; i++) {
      final v = _todayVisits[i];
      if (_completedVisitIds.contains(v.id)) continue;

      final d = distance.as(
        LengthUnit.Meter,
        currentPosition,
        LatLng(v.latitude, v.longitude),
      );
      if (d < minDistance) {
        minDistance = d;
        bestIndex = i;
      }
    }

    if (bestIndex != null) {
      _currentVisitIndex = bestIndex;
      notifyListeners();
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:45 UTC-5 (Lima)][desc: Guarda orden de visitas][obj: VisitController.saveOrder]
  Future<void> saveOrder(String uid, List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'visit_order_$uid';
    await prefs.setStringList(key, ids);
  }

  void checkSmartAlerts(LatLng currentPosition) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 15:40 UTC-5 (Lima)][desc: Lógica de Alertas Inteligentes: calcula ETA y avisa si peligra una cita pactada][obj: VisitController.checkSmartAlerts]
    final now = DateTime.now();
    
    // Throttle checks to every 5 minutes to save battery
    if (_lastSmartAlertCheck != null && 
        now.difference(_lastSmartAlertCheck!).inMinutes < 5) {
      return;
    }
    _lastSmartAlertCheck = now;

    if (_todayVisits.isEmpty) return;

    final dist = const Distance();
    
    for (final v in _todayVisits) {
      // Only check pending visits with a scheduled time
      if (_completedVisitIds.contains(v.id)) continue;
      if (v.scheduledAt == null) continue;

      final target = LatLng(v.latitude, v.longitude);
      final distanceKm = dist.as(LengthUnit.Kilometer, currentPosition, target);
      
      // Assume average speed of 20 km/h in city + 10 min margin
      final estimatedTravelMinutes = (distanceKm / 20 * 60).round();
      final marginMinutes = 10;
      final totalNeededMinutes = estimatedTravelMinutes + marginMinutes;
      
      final timeToAppointment = v.scheduledAt!.difference(now).inMinutes;

      if (timeToAppointment > 0 && timeToAppointment <= totalNeededMinutes) {
        logDebug('Smart Alert triggered', details: 'visit=${v.name} timeToAppt=$timeToAppointment needed=$totalNeededMinutes');
        // Trigger alert via callback
        if (onSmartAlert != null) {
          // We need to find the VisitItem from the plan if possible, or just use AssignedVisit
          // For now, we'll use a dummy VisitItem or update the callback signature
          // Let's update the callback to use AssignedVisit for simplicity here
          _triggerSmartAlert(v, v.scheduledAt!);
        }
      }
    }
  }

  void _triggerSmartAlert(AssignedVisit visit, DateTime time) {
    // Convert AssignedVisit to a minimal VisitItem for the UI if needed
    final item = VisitItem(
      id: int.tryParse(visit.id) ?? 0,
      companyName: visit.name,
      targetTime: time,
      orderIndex: 0,
      state: VisitItemState.pending,
      startTime: null,
      endTime: null,
      address: visit.address,
    );
    onSmartAlert?.call(item, time);
  }

}
