import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import '../../models/cuestionario.dart';
import '../../models/visit_plan.dart';
import '../../models/location_point.dart';
import '../../services/api_service.dart';
import '../../services/offline_visit_event_store.dart';
import '../../services/visit_plan_cache_store.dart';
import '../../services/questionnaire_cache_store.dart';
import '../../services/offline_sync_status.dart';
import '../../services/offline_questionnaire_store.dart';
import '../../services/visit_state_sync_manager.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../utils/logger.dart';
import '../../services/telemetry_log_service.dart';
import 'questionnaire_screen.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';

class VisitPlanScreen extends StatefulWidget {
  const VisitPlanScreen({
    super.key,
    required this.apiService,
    this.currentLocation,
    this.canOptimize = true,
  });

  final ApiService apiService;
  final ll.LatLng? currentLocation;
  final bool canOptimize;

  @override
  State<VisitPlanScreen> createState() => _VisitPlanScreenState();
}

class _VisitPlanScreenState extends State<VisitPlanScreen> {
  VisitPlan? _plan;
  bool _loading = true;
  bool _reordering = false;
  bool _saving = false;
  bool _optimizing = false;
  String? _error;
  String? _warning;
  final VisitPlanCacheStore _cache = VisitPlanCacheStore();
  final QuestionnaireCacheStore _questionnaireCache = QuestionnaireCacheStore();
  final OfflineVisitEventStore _eventStore = OfflineVisitEventStore();
  final OfflineQuestionnaireStore _questionnaireStore = OfflineQuestionnaireStore();
  Set<int> _pendingSyncIds = const {};
  Map<int, int> _pendingQuestionnaireCounts = const {};
  final OfflineSyncStatus _syncStatus = GetIt.I<OfflineSyncStatus>();
  bool _syncing = false;
  DateTime? _lastSyncToastAt;

  @override
  void initState() {
    super.initState();
    logDebug('VisitPlanScreen init -> load plan');
    _syncStatus.addListener(_onSyncStatusChanged);
    _syncThenLoad();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 09:00 UTC-5 (Lima)][desc: Espera que el sync complete antes de cargar el plan, para que el API devuelva el estado más reciente][obj: VisitPlanScreen._syncThenLoad]
  Future<void> _syncThenLoad() async {
    await GetIt.I<VisitStateSyncManager>().syncOnce();
    _loadPlan();
  }

  @override
  void dispose() {
    _syncStatus.removeListener(_onSyncStatusChanged);
    super.dispose();
  }

  void _onSyncStatusChanged() {
    if (!mounted) return;
    final completedAt = _syncStatus.lastCompletedAt;
    if (completedAt != null &&
        _syncStatus.lastHadPending &&
        (_lastSyncToastAt == null || completedAt.isAfter(_lastSyncToastAt!))) {
      _lastSyncToastAt = completedAt;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sincronización completada')),
      );
    }
    setState(() {
      _syncing = _syncStatus.syncing && _syncStatus.hasPending;
    });
  }

  Future<void> _loadPlan() async {
    setState(() {
      _loading = true;
      _error = null;
      _warning = null;
      _plan = null; // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-12 11:45 UTC-5 (Lima)][desc: Limpia plan para forzar fetch fresco en reintentos][obj: VisitPlanScreen._loadPlan]
    });
    final backendCheck = widget.apiService.checkBackendAvailable(
      timeout: const Duration(seconds: 5),
    );
    try {
      /*final backendOk = await widget.apiService.checkBackendAvailable(
        timeout: const Duration(seconds: 3),
      );
      if (!backendOk) {
        final cached = await _cache.loadLatest();
        if (cached != null && _isTodayLima(cached.plannedFor)) {
          logWarn('VisitPlanScreen: usando plan en cache', details: 'planId=${cached.id}');
          setState(() {
            _plan = cached;
            _warning = 'Mostrando plan sin conexión.';
          });
          await _loadPendingSyncIds();
          return;
        }
        // Cache existe pero no es de hoy (o plannedFor nulo) → no mostrar plan pasado
        setState(() {
          _plan = null;
          _error = 'No tienes un plan de visitas asignado para hoy.';
        });
        return;
      }*/

      final plan = await widget.apiService.fetchVisitPlanForMe();
      if (!mounted) return;
      logDebug(
        'VisitPlanScreen plan cargado',
        details: 'items=${plan.items.length} id=${plan.id} plannedFor=${plan.plannedFor}',
      );
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: Valida que el plan sea del día de hoy (hora Lima) para no mostrar planes de días anteriores][obj: VisitPlanScreen._loadPlan date guard]
      if (!_isTodayLima(plan.plannedFor)) {
        logWarn(
          'VisitPlanScreen: plan no es de hoy',
          details: 'plannedFor=${plan.plannedFor}',
        );
        setState(() {
          _plan = null;
          _error = 'No tienes un plan de visitas asignado para hoy.';
        });
        return;
      }
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 09:00 UTC-5 (Lima)][desc: Preserva estados locales de items con eventos pendientes/error al guardar plan del API, evita mostrar estado desactualizado en Mi Jornada][obj: VisitPlanScreen._loadPlan merge pending states]
      final unsyncedEvents = await _eventStore.fetchPending();
      VisitPlan planToShow = plan;
      if (unsyncedEvents.isNotEmpty) {
        final latestStateByVisit = <int, VisitItemState>{};
        for (final event in unsyncedEvents) {
          latestStateByVisit[event.visitId] = VisitItemState.fromApi(event.eventType);
        }
        final mergedItems = plan.items.map((item) {
          final localState = latestStateByVisit[item.id];
          return localState != null ? item.copyWith(state: localState) : item;
        }).toList();
        planToShow = plan.copyWith(items: mergedItems);
      }
      await _cache.savePlan(planToShow);
      setState(() => _plan = planToShow);
      await _loadPendingSyncIds();
    } catch (e, st) {
      logError('Error cargando plan', error: e, stackTrace: st);
      if (!mounted) return;
      final cached = await _cache.loadLatest();
      if (cached != null && _isTodayLima(cached.plannedFor)) {
        logWarn('VisitPlanScreen: usando plan en cache', details: 'planId=${cached.id}');
        setState(() {
          _plan = cached;
          _warning = 'Mostrando plan sin conexión.';
        });
        await _loadPendingSyncIds();
      } else {
        final msg = e.toString();
        final friendly = msg.contains('El verificador no cuenta con un Plan de Visitas asignado') ||
                msg.contains('No tienes un plan de visitas asignado')
            ? 'No tienes un plan de visitas asignado para hoy.'
            : msg;
        setState(() {
          _plan = null;
          _error = friendly;
        });
        logWarn('VisitPlanScreen plan no cargado', details: friendly);
      }
    } finally {
      try {
        final ok = await backendCheck;
        if (!ok && mounted && _error == null) {
          setState(() {
            _warning = _warning ?? 'Backend inestable. Mostrando información local si es posible.';
          });
        }
      } catch (_) {}
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final plan = _plan;
    if (plan == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 15:34 UTC-5 (Lima)][desc: Bloquea movimiento de visitas ya iniciadas o completadas][obj: VisitPlanScreen._onReorder]
    if (plan.items[oldIndex].state != VisitItemState.pending) {
      _showSnack('No se pueden mover visitas ya iniciadas o completadas.');
      return;
    }

    final items = List.of(plan.items);
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 15:34 UTC-5 (Lima)][desc: Valida jerarquía estricta de prioridades al reordenar][obj: VisitPlanScreen._onReorder priority]
    if (!_isOrderAllowedByPriority(items)) {
      _showSnack('No se permite colocar prioridades bajas antes de altas.');
      return;
    }
    
    if (!_isOrderAllowedByState(plan.items, items)) {
      _showSnack('No se pueden desplazar visitas que ya están en curso.');
      return;
    }

    // Optimistic ordering locally
    final reordered = <VisitItem>[];
    for (var i = 0; i < items.length; i++) {
      reordered.add(items[i].copyWith(orderIndex: i + 1));
    }
    setState(() => _plan = plan.copyWith(items: reordered));
    setState(() => _reordering = true);
    try {
      final updated = await widget.apiService.reorderVisitItems(
        planId: plan.id,
        itemIds: reordered.map((e) => e.id).toList(),
      );
      if (!mounted) return;
      setState(() => _plan = updated);
      _showSnack('Orden actualizado');
    } catch (e, st) {
      logError('Error reordenando', error: e, stackTrace: st);
      if (!mounted) return;
      _showSnack('No se pudo guardar el orden: $e');
      await _loadPlan();
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<void> _optimizeFreeBlocks() async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 15:35 UTC-5 (Lima)][desc: Algoritmo de optimización por distancia respetando prioridades y GPS][obj: VisitPlanScreen._optimizeFreeBlocks]
    final plan = _plan;
    if (plan == null || _optimizing) return;
    setState(() => _optimizing = true);

    try {
      final items = List.of(plan.items);
      final dist = ll.Distance();
      
      // Helper to compute distance
      double d(ll.LatLng p1, double? lat, double? lng) {
        if (lat == null || lng == null) return double.infinity;
        return dist.as(ll.LengthUnit.Kilometer, p1, ll.LatLng(lat, lng));
      }

      // We only optimize pending visits. Locked visits (started/done) stay put.
      final pendingIndices = <int>[];
      for (var i = 0; i < items.length; i++) {
        if (items[i].state == VisitItemState.pending) {
          pendingIndices.add(i);
        }
      }

      if (pendingIndices.length < 2) {
        _showSnack('No hay suficientes visitas pendientes para optimizar.');
        return;
      }

      // Group by priority
      final byPriority = <int, List<int>>{}; // Rank -> Indices
      for (final idx in pendingIndices) {
        final rank = _priorityRank(items[idx].prioridad);
        byPriority.putIfAbsent(rank, () => []).add(idx);
      }

      final sortedRanks = byPriority.keys.toList()..sort();

      final hasPendingCoords = pendingIndices.any((i) =>
          items[i].latitude != null && items[i].longitude != null);
      if (widget.currentLocation == null && !hasPendingCoords) {
        _showSnack('No hay coordenadas para optimizar; se mantiene el orden actual.');
        return;
      }

      final optimizedPending = <VisitItem>[];

      ll.LatLng refPoint = widget.currentLocation ??
          (() {
            final firstWithCoords = pendingIndices.firstWhere(
              (i) => items[i].latitude != null && items[i].longitude != null,
            );
            return ll.LatLng(items[firstWithCoords].latitude!, items[firstWithCoords].longitude!);
          })();

      for (final rank in sortedRanks) {
        final group = byPriority[rank]!;
        final remaining = group.toSet();
        
        while (remaining.isNotEmpty) {
          int? bestIdx;
          double bestDist = double.infinity;
          for (final idx in remaining) {
            final di = d(refPoint, items[idx].latitude, items[idx].longitude);
            if (di < bestDist) {
              bestDist = di;
              bestIdx = idx;
            }
          }
          final chosen = bestIdx ?? remaining.first;
          optimizedPending.add(items[chosen]);
          if (items[chosen].latitude != null) {
            refPoint = ll.LatLng(items[chosen].latitude!, items[chosen].longitude!);
          }
          remaining.remove(chosen);
        }
      }

      // Update order indexes
      final finalItems = <VisitItem>[];
      var pendingCursor = 0;
      for (var i = 0; i < items.length; i++) {
        if (items[i].state == VisitItemState.pending) {
          finalItems.add(optimizedPending[pendingCursor].copyWith(orderIndex: i + 1));
          pendingCursor++;
        } else {
          finalItems.add(items[i].copyWith(orderIndex: i + 1));
        }
      }

      setState(() => _plan = plan.copyWith(items: finalItems));
      
      // Save to server
      final updated = await widget.apiService.reorderVisitItems(
        planId: plan.id,
        itemIds: finalItems.map((e) => e.id).toList(),
      );
      setState(() => _plan = updated);
      _showSnack('Ruta optimizada por prioridad y distancia');
    } catch (e) {
      _showSnack('Error al optimizar: $e');
      await _loadPlan();
    } finally {
      if (mounted) setState(() => _optimizing = false);
    }
  }

  Future<void> _startVisit(VisitItem item) async {
    if (_saving) return;
    setState(() => _saving = true);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-07 10:03 UTC-5 (Lima)][desc: Delega el cambio de estado al flujo del mapa para permitir cancelar antes de marcar EN_ROUTE][obj: VisitPlanScreen._startVisit]
    if (mounted) {
      Navigator.of(context).pop(item);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:16 UTC-5 (Lima)][desc: Confirma llegada desde lista del plan validando radio actual][obj: VisitPlanScreen confirm arrival]
  Future<void> _confirmArrivalFromPlan(VisitItem item) async {
    GetIt.I<TelemetryLogService>().log(
      'Entrada a _confirmArrivalFromPlan: itemId=${item.id} empresa=${item.companyName} lat=${item.latitude} lng=${item.longitude} estado=${item.state}',
    );
    if (_saving) return;
    final lat = item.latitude;
    final lng = item.longitude;
    if (lat == null || lng == null) {
      _showSnack('El destino no tiene coordenadas registradas.');
      return;
    }
    final current = widget.currentLocation ??
        await _currentLocationFromService();
    if (!mounted) return;
    if (current == null) {
      _showSnack('No se pudo obtener la ubicación actual.');
      return;
    }
    final radius = await _loadArrivalRadiusMeters();
    if (!mounted) return;
    final distance = ll.Distance().distance(
      ll.LatLng(lat, lng),
      current,
    );
    if (distance > radius) {
      _showSnack(
        'Aún no estás dentro del radio de ${radius.toStringAsFixed(0)} m.',
      /*final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fuera del radio'),
          content: Text(
            'Estás a ${distance.toStringAsFixed(0)} m del destino. '
            'El radio configurado es ${radius.toStringAsFixed(0)} m.\n\n'
            '¿Deseas confirmar la llegada de todos modos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirmar igual'),
            ),
          ],
        ),*/
      ); return;

      /*if (proceed != true) {
        _showSnack(
          'Aún no estás dentro del radio de ${radius.toStringAsFixed(0)} m.',
        );
        return;
      }*/
    }

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Llegaste a tu destino?'),
        content: Text(
          'Te encuentras dentro del radio de ${radius.toStringAsFixed(0)} m del destino.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    setState(() => _saving = true);
    try {
      await _queueOfflineState(item, VisitItemState.onSite, current);
      final updated = item.copyWith(state: VisitItemState.onSite);
      _replaceItem(updated);
      await _cache.updateItemState(itemId: updated.id, newState: updated.state);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-20 UTC-5 (Lima)][desc: Deshabilita alerta nativa al confirmar llegada desde el plan][obj: VisitPlanScreen._confirmArrivalFromPlan disable native]
      unawaited(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('arrival_target_enabled', false);
        } catch (_) {}
      }());
      GetIt.I<VisitStateSyncManager>().triggerNow();
      _showSnack('Llegada registrada. Se sincronizará.');
      if (mounted) {
        await _promptStartVisitFromPlan(updated);
      }
    } catch (e, st) {
      logError('Error confirmando llegada', error: e, stackTrace: st);
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:16 UTC-5 (Lima)][desc: Pide confirmación antes de iniciar visita desde la lista][obj: VisitPlanScreen start visit prompt]
  Future<void> _promptStartVisitFromPlan(VisitItem item) async {
    if (!mounted) return;
    final startNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Deseas iniciar la visita?'),
        content: const Text(
          'Puedes iniciar ahora o hacerlo luego.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Luego'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Iniciar ahora'),
          ),
        ],
      ),
    );
    if (startNow == true) {
      await _startVisitNow(item);
    } else {
      _showSnack('Puedes iniciar la visita cuando estés listo.');
      if (mounted) {
        Navigator.of(context).pop(item);
      }
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:16 UTC-5 (Lima)][desc: Inicia visita desde lista cuando ya se confirmó llegada (ON_SITE)][obj: VisitPlanScreen start visit]
  Future<void> _startVisitNow(VisitItem item) async {
    if (_saving) return;
    setState(() => _saving = true);
    final current = await GetIt.I<LocationService>().getCurrentOnce();
    try {
      await _queueOfflineState(item, VisitItemState.inVisit, _toLatLng(current));
      final updated = item.copyWith(state: VisitItemState.inVisit);
      _replaceItem(updated);
      await _cache.updateItemState(itemId: updated.id, newState: updated.state);
      GetIt.I<VisitStateSyncManager>().triggerNow();
      _showSnack('Visita iniciada. Se sincronizará.');
      if (mounted) {
        Navigator.of(context).pop(updated);
      }
    } catch (e, st) {
      logError('Error iniciando visita', error: e, stackTrace: st);
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:16 UTC-5 (Lima)][desc: Obtiene ubicación actual para validar llegada desde el plan][obj: VisitPlanScreen current location]
  Future<ll.LatLng?> _currentLocationFromService() async {
    final current = await GetIt.I<LocationService>().getCurrentOnce();
    if (current == null) return null;
    return ll.LatLng(current.latitude, current.longitude);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:16 UTC-5 (Lima)][desc: Lee radio de llegada configurado para validar confirmación][obj: VisitPlanScreen arrival radius]
  Future<double> _loadArrivalRadiusMeters() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('arrival_radius_m') ?? 50.0;
  }

  Future<void> _completeVisit(VisitItem item) async {
    if (_saving) return;
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Homologa flujo Mi Jornada con el flujo del mapa: culminación → cuestionario/formulario cierre → DONE][obj: VisitPlanScreen._completeVisit]
    final culmino = await _showCulminacionDialog(item);
    if (culmino != true) return; // No o cancelado: cierra modal, botón sigue activo
    final cuestionarioOk = await _handleCuestionarioAsignado(item);
    if (!cuestionarioOk) return;

    setState(() => _saving = true);
    final current = await GetIt.I<LocationService>().getCurrentOnce();
    try {
      await _queueOfflineState(item, VisitItemState.done, _toLatLng(current));
      final updated = item.copyWith(state: VisitItemState.done);
      final plan = _plan;
      List<VisitItem>? updatedItems;
      if (plan != null) {
        updatedItems = plan.items
            .map((i) => i.id == updated.id ? updated : i)
            .toList();
      }
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Sync no bloqueante igual que mapa; _queueOfflineState ya actualiza cache y UI][obj: VisitPlanScreen._completeVisit sync]
      GetIt.I<VisitStateSyncManager>().triggerNow();
      _showSnack('Visita completada. Se sincronizará.');
      if (mounted) {
        VisitItem? nextItem;
        if (updatedItems != null) {
          for (final candidate in updatedItems) {
            if (candidate.id == updated.id) continue;
            if (candidate.state == VisitItemState.done ||
                candidate.state == VisitItemState.cancelled) {
              continue;
            }
            nextItem = candidate;
            break;
          }
        }
        if (nextItem != null) {
          final nextLabel = nextItem.companyName.isNotEmpty
              ? nextItem.companyName
              : 'la siguiente visita';
          final goNext = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Verificación completada'),
              content: Text('¿Deseas pasar a la siguiente visita?\n\nSiguiente: $nextLabel'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('No'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Sí, siguiente'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (goNext == true && mounted) {
            Navigator.of(context).pop(nextItem);
            return;
          }
        }
        if (!mounted) return;
        Navigator.of(context).pop(updated);
      }
    } catch (e, st) {
      logError('Error completando visita', error: e, stackTrace: st);
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:25 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: VisitPlanScreen._handleCuestionarioAsignado]
  Future<bool> _handleCuestionarioAsignado(VisitItem item) async {
    try {
      Cuestionario? cuestionario;
      List<Pregunta> preguntas = const [];
      try {
        cuestionario = await widget.apiService.fetchCuestionarioActivo();
        if (cuestionario != null) {
          preguntas = await widget.apiService.fetchPreguntasPorCuestionario(
            cuestionario.id,
          );
          await _questionnaireCache.save(
            cuestionario: cuestionario,
            preguntas: preguntas,
          );
        }
      } catch (_) {
        final cached = await _questionnaireCache.loadLatest();
        if (cached != null) {
          cuestionario = cached.cuestionario;
          preguntas = cached.preguntas;
        }
      }
      if (cuestionario == null) {
        _showSnack('No hay cuestionario disponible sin conexión.');
        return false;
      }
      if (!mounted) return false;
      if (preguntas.isEmpty) {
        _showSnack('El cuestionario activo no tiene preguntas.');
        return true;
      }
      final personaId = await _resolvePersonaId();
      if (!mounted) return false;
      if (personaId == null) {
        _showSnack('No se pudo identificar al usuario para registrar respuestas.');
        return false;
      }
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => QuestionnaireScreen(
            cuestionario: cuestionario!,
            preguntas: preguntas,
            apiService: widget.apiService,
            idPersona: personaId,
            idItem: item.id,
            visitLabel: item.companyName,
          ),
        ),
      );
      return completed == true;
    } catch (e, st) {
      logError('Error cargando cuestionario', error: e, stackTrace: st);
      _showSnack('No se pudo cargar el cuestionario: $e');
      return false;
    }
  }

  Future<bool> _ensureBackendAvailable({String? actionLabel}) async {
    try {
      final token = await GetIt.I<AuthService>().ensureValidToken();
      await widget.apiService.updateAuthToken(token);
    } catch (_) {}
    final ok = await widget.apiService.checkBackendAvailable();
    if (ok) return true;
    if (!mounted) return false;
    final msg =
        'Estamos presentando fallas con la conexión de autorización. Por favor vuelve a intentarlo nuevamente.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    return false;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:25 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: VisitPlanScreen._resolvePersonaId]
  Future<int?> _resolvePersonaId() async {
    final session = GetIt.I<AuthService>().currentSession;
    String? uid = session?.uid;
    if (uid == null || uid.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      uid = prefs.getString('auth_uid');
    }
    if (uid == null || uid.isEmpty) {
      return null;
    }
    final profile = await widget.apiService.fetchUserProfile(uid);
    return profile?.id;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:42 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: VisitPlanScreen._showRespuestasDialog]
  Future<void> _showRespuestasDialog(VisitItem item) async {
    final future = _loadRespuestasDialogData(item);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Respuestas - ${item.companyName}'),
          content: FutureBuilder<_RespuestasDialogData?>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Text('No se pudieron cargar las respuestas: ${snapshot.error}');
              }
              final data = snapshot.data;
              if (data == null) {
                return const Text('No hay cuestionario activo para mostrar.');
              }
              if (data.respuestas.isEmpty) {
                return Text('No hay respuestas registradas para ${data.cuestionarioNombre}.');
              }
              return SizedBox(
                width: double.maxFinite,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: data.respuestas.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final respuesta = data.respuestas[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          respuesta.textoPregunta,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(respuesta.respuesta),
                      ],
                    );
                  },
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:42 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: VisitPlanScreen._loadRespuestasDialogData]
  Future<_RespuestasDialogData?> _loadRespuestasDialogData(VisitItem item) async {
    final cuestionario = await widget.apiService.fetchCuestionarioActivo();
    if (cuestionario == null) {
      return null;
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-22 09:23 UTC-5 (Lima)][desc: Consulta respuestas filtradas por item de visita][obj: VisitPlanScreen._loadRespuestasDialogData]
    final respuestas = await widget.apiService.fetchRespuestasPorItem(
      idItem: item.id,
    );
    return _RespuestasDialogData(
      cuestionarioNombre: cuestionario.nombre,
      respuestas: respuestas,
    );
  }

  void _replaceItem(VisitItem updated) {
    final plan = _plan;
    if (plan == null) return;
    final nextItems = plan.items
        .map((i) => i.id == updated.id ? updated : i)
        .toList();
    String newStatus = plan.status;
    final allDone =
        nextItems.isNotEmpty &&
        nextItems.every((i) => i.state == VisitItemState.done);
    final anyInVisit = nextItems.any((i) => i.state == VisitItemState.inVisit);
    if (allDone) {
      newStatus = 'COMPLETED';
    } else if (anyInVisit) {
      newStatus = 'IN_PROGRESS';
    }
    setState(() => _plan = plan.copyWith(items: nextItems, status: newStatus));
  }

  Future<void> _queueOfflineState(
    VisitItem item,
    VisitItemState state,
    ll.LatLng? current,
  ) async {
    await _eventStore.enqueue(
      visitId: item.id,
      eventType: state.apiValue,
      timestamp: DateTime.now(),
      latitude: current?.latitude,
      longitude: current?.longitude,
    );
    _replaceItem(item.copyWith(state: state));
    await _cache.updateItemState(itemId: item.id, newState: state);
    await _loadPendingSyncIds();
  }

  ll.LatLng? _toLatLng(LocationPoint? point) {
    if (point == null) return null;
    return ll.LatLng(point.latitude, point.longitude);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: Compara plannedFor con la fecha de hoy en zona Lima (UTC-5) para evitar mostrar planes de días anteriores][obj: VisitPlanScreen._isTodayLima]
  static bool _isTodayLima(DateTime? plannedFor) {
    if (plannedFor == null) return false;
    final nowLima = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final planLima = plannedFor.toUtc().subtract(const Duration(hours: 5));
    return nowLima.year == planLima.year &&
        nowLima.month == planLima.month &&
        nowLima.day == planLima.day;
  }

  Future<void> _loadPendingSyncIds() async {
    try {
      final pending = await _eventStore.fetchPendingVisitIds();
      final pendingQuestionnaires = await _questionnaireStore.fetchPendingCountsByVisit();
      if (!mounted) return;
      setState(() {
        _pendingSyncIds = pending;
        _pendingQuestionnaireCounts = pendingQuestionnaires;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
                        title: const Text('Mi Jornada'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadPlan,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null && plan == null)
              ? _ErrorState(message: _error!, onRetry: _loadPlan)
              : plan == null
                  ? const _ErrorState(message: 'El verificador no cuenta con un plan de visitas asignado.')
                  : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_warning != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: Colors.amber.shade100,
                    child: Text(
                      _warning!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.brown.shade800),
                    ),
                  ),
                if (_syncing)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: Colors.blueGrey.shade50,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.blueGrey.shade400,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Sincronizando…',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: Colors.blueGrey.shade500),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title?.isNotEmpty == true
                            ? plan.title!
                            : 'Plan #${plan.id}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Estado: ${plan.status}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (plan.plannedFor != null)
                        Text(
                          'Programado: ${_fmtDate(plan.plannedFor!)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (_reordering || _saving || _optimizing)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(_optimizing ? 'Optimizando ruta...' : 'Sincronizando cambios...'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (plan.items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Orden de visitas',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Tooltip(
                          message: widget.canOptimize
                              ? 'Optimizar ruta'
                              : 'Esperando ubicación GPS para optimizar',
                          child: ElevatedButton.icon(
                            onPressed: (_loading || _optimizing || _reordering || !widget.canOptimize)
                                ? null
                                : _optimizeFreeBlocks,
                            icon: const Icon(Icons.auto_fix_high, size: 18),
                            label: const Text('Optimizar ruta'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: plan.items.isEmpty
                      ? const Center(child: Text('No hay visitas en el plan.'))
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          onReorder: _onReorder,
                          itemCount: plan.items.length,
                          buildDefaultDragHandles: false,
                          itemBuilder: (context, index) {
                            final item = plan.items[index];
                            final locked = item.state != VisitItemState.pending;
                            final isDone = item.state == VisitItemState.done;
                            final pendingSync = _pendingSyncIds.contains(item.id);
                            final pendingQuestionnaireCount = _pendingQuestionnaireCounts[item.id] ?? 0;
                            final pendingQuestionnaire = pendingQuestionnaireCount > 0;
                            final itemSyncing = _syncing && pendingSync;
                            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:16 UTC-5 (Lima)][desc: Evita mostrar inicio del siguiente item mientras hay visita en curso][obj: VisitPlanScreen start button gating]
                            final hasInProgress = plan.items.any(
                              (i) =>
                                  i.state == VisitItemState.enRoute ||
                                  i.state == VisitItemState.onSite ||
                                  i.state == VisitItemState.inVisit,
                            );
                            final firstPending = _firstPendingIndex(plan.items);
                            logDebug(
                              'VisitPlanScreen action gating',
                              details:
                                  'index=$index id=${item.id} state=${item.state} hasInProgress=$hasInProgress firstPending=$firstPending',
                            );
                            return Card(
                              key: ValueKey(item.id),
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:42 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: VisitPlanScreen detalle respuestas]
                                onTap: isDone ? () => _showRespuestasDialog(item) : null,
                                leading: SizedBox(
                                  width: 52,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _priorityRingColor(item.prioridad) ??
                                                Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                        child: CircleAvatar(
                                          radius: 12,
                                          child: Text(
                                            '${index + 1}',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (locked)
                                            const Icon(
                                              Icons.lock,
                                              size: 12,
                                              color: Colors.grey,
                                            ),
                                          if (isDone)
                                            const Padding(
                                              padding: EdgeInsets.only(left: 2),
                                              child: Icon(
                                                Icons.check_circle,
                                                size: 12,
                                                color: Colors.green,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                title: Text(
                                  item.companyName,
                                  style: isDone
                                      ? const TextStyle(
                                          decoration: TextDecoration.lineThrough,
                                          color: Colors.grey,
                                        )
                                      : Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: _StateChip(state: item.state),
                                      ),
                                    ),
                                    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Muestra la dirección real del plan (antes era un label hardcodeado)][obj: VisitPlanScreen itemBuilder direccion]
                                    if (item.address != null &&
                                        item.address!.trim().isNotEmpty)
                                      Text(
                                        'Dirección: ${item.address}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (item.targetTime != null)
                                      Text(
                                        'Hora de Cita: ${_fmtHour(item.targetTime!)}',
                                      ),
                                    if (item.startTime != null)
                                      Text('Inicio: ${_fmtHour(item.startTime!)}'),
                                    if (item.endTime != null)
                                      Text('Fin: ${_fmtHour(item.endTime!)}'),
                                    if (item.complex != null)
                                      Text(
                                        'Compleja: ${item.complex == true ? 'Sí' : 'No'}',
                                      ),
                                    if (item.foundProblem != null)
                                      Text(
                                        'Problema: ${item.foundProblem == true ? 'Sí' : 'No'}',
                                      ),
                                    if (item.problemNote != null &&
                                        item.problemNote!.isNotEmpty)
                                      Text('Detalle: ${item.problemNote}'),
                                    if (item.otherInfo != null &&
                                        item.otherInfo!.isNotEmpty)
                                      Text('Info: ${item.otherInfo}'),
                                    if (item.plantillaPv != null &&
                                        item.plantillaPv!.trim().isNotEmpty)
                                      Text(
                                        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 12:52 UTC-5 (Lima)][desc: Muestra plantilla del plan de visitas en el listado][obj: VisitPlanScreen plantillaPv]
                                        'Plantilla: ${item.plantillaPv}',
                                      ),
                                    if (item.prioridad != null &&
                                        item.prioridad!.trim().isNotEmpty)
                                      Text(
                                        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-07 14:39 UTC-5 (Lima)][desc: Muestra prioridad debajo de cada item del plan de visitas][obj: VisitPlanScreen prioridad]
                                        'Prioridad: ${item.prioridad}',
                                      ),
                                    if (pendingSync)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.cloud_upload_outlined,
                                              size: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Pendiente de sincronizar',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (pendingQuestionnaire)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.assignment_turned_in_outlined,
                                              size: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              pendingQuestionnaireCount > 1
                                                  ? 'Cuestionario pendiente ($pendingQuestionnaireCount)'
                                                  : 'Cuestionario pendiente',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (itemSyncing)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.blueGrey.shade400,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Sincronizando…',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(color: Colors.blueGrey.shade500),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (isDone)
                                      const Text(
                                        'Ver respuestas del cuestionario',
                                        style: TextStyle(
                                          color: Colors.blueGrey,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                                 trailing: Row(
                                   mainAxisSize: MainAxisSize.min,
                                   children: [
                                     // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:16 UTC-5 (Lima)][desc: Ajusta acciones por estado: ir, confirmar llegada, iniciar visita][obj: VisitPlanScreen action buttons]
                                     if (item.state == VisitItemState.enRoute ||
                                         item.state == VisitItemState.onSite ||
                                         (item.state == VisitItemState.pending &&
                                             !hasInProgress &&
                                             _firstPendingIndex(plan.items) ==
                                                 index))
                                       TextButton(
                                         onPressed: _saving
                                             ? null
                                             : () {
                                                 if (item.state ==
                                                     VisitItemState.enRoute) {
                                                   _confirmArrivalFromPlan(item);
                                                   return;
                                                 }
                                                 if (item.state ==
                                                     VisitItemState.onSite) {
                                                   _promptStartVisitFromPlan(item);
                                                   return;
                                                 }
                                                 final reason = _startBlockedReason(
                                                   item,
                                                   plan.items,
                                                 );
                                                 if (reason != null) {
                                                   _showSnack(reason);
                                                   return;
                                                 }
                                                 _startVisit(item);
                                               },
                                        child: Text(
                                          item.state == VisitItemState.enRoute
                                              ? 'Confirmar llegada'
                                              : item.state ==
                                                      VisitItemState.onSite
                                                  ? 'Iniciar visita'
                                                  : 'Ir al lugar',
                                        ),
                                       ),
                                     if (item.state == VisitItemState.inVisit)
                                       ElevatedButton(
                                         onPressed: _saving
                                             ? null
                                             : () => _completeVisit(item),
                                         child: const Text('Completar'),
                                       ),
                                     if (!locked)
                                       ReorderableDragStartListener(
                                         index: index,
                                         child: const Padding(
                                           padding: EdgeInsets.only(left: 8),
                                           child: Icon(
                                             Icons.drag_indicator,
                                             color: Colors.grey,
                                           ),
                                         ),
                                       ),
                                   ],
                                 ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  int _priorityRank(String? raw) {
    final key = (raw ?? '').toUpperCase();
    if (key.contains('MUY')) return 0;
    if (key.contains('ALTA')) return 1;
    return 2;
  }

  bool _isOrderAllowedByPriority(List<VisitItem> items) {
    int lastRank = -1;
    for (final item in items) {
      final rank = _priorityRank(item.prioridad);
      if (rank < lastRank) return false;
      lastRank = rank;
    }
    return true;
  }

  Color? _priorityRingColor(String? raw) {
    final key = (raw ?? '').toUpperCase();
    if (key.contains('MUY')) return Colors.red.shade700;
    if (key.contains('ALTA')) return Colors.orange.shade700;
    if (key.contains('NORMAL')) return Colors.grey.shade600;
    return null;
  }

  int _firstPendingIndex(List<VisitItem> items) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-07 15:23 UTC-5 (Lima)][desc: Restringe botón Iniciar al primer item pendiente según orden][obj: VisitPlanScreen._firstPendingIndex]
    for (var i = 0; i < items.length; i++) {
      if (items[i].state == VisitItemState.pending) {
        return i;
      }
    }
    return -1;
  }

  bool _isOrderAllowedByState(List<VisitItem> original, List<VisitItem> reordered) {
    final lockedIds = original
        .where((i) => i.state != VisitItemState.pending)
        .map((i) => i.id)
        .toList();
    for (final id in lockedIds) {
      final originalIndex = original.indexWhere((i) => i.id == id);
      final newIndex = reordered.indexWhere((i) => i.id == id);
      if (originalIndex != newIndex) return false;
    }
    return true;
  }

  String? _startBlockedReason(VisitItem item, List<VisitItem> items) {
    if (item.state == VisitItemState.inVisit ||
        item.state == VisitItemState.done ||
        item.state == VisitItemState.cancelled) {
      return 'La visita ya fue iniciada.';
    }
    final currentRank = _priorityRank(item.prioridad);
    for (final other in items) {
      if (other.id == item.id) continue;
      if (other.state == VisitItemState.inVisit ||
          other.state == VisitItemState.enRoute ||
          other.state == VisitItemState.onSite) {
        return 'Ya hay una visita en curso.';
      }
    }
    if (item.state == VisitItemState.pending) {
      for (final other in items) {
        if (other.id == item.id) continue;
        if (other.state != VisitItemState.pending) continue;
        final otherRank = _priorityRank(other.prioridad);
        if (otherRank < currentRank) {
          return 'Debes iniciar primero las visitas de mayor prioridad.';
        }
        if (otherRank == currentRank &&
            other.orderIndex < item.orderIndex) {
          return 'Debes iniciar primero la visita de orden ${other.orderIndex}.';
        }
      }
    }
    return null;
  }

  String _fmtDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _fmtHour(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<bool?> _showCulminacionDialog(VisitItem item) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Pregunta si desea culminar la visita; No cierra el modal sin avanzar, Sí va al cuestionario][obj: VisitPlanScreen._showCulminacionDialog]
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Completar visita'),
        content: const Text('¿Deseas culminar con la visita?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
  }

}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final VisitItemState state;

  Color _color(BuildContext context) {
    switch (state) {
      case VisitItemState.done:
        return Colors.green.shade100;
      case VisitItemState.inVisit:
        return Colors.blue.shade100;
      case VisitItemState.enRoute:
      case VisitItemState.onSite:
        return Colors.orange.shade100;
      case VisitItemState.cancelled:
        return Colors.grey.shade300;
      case VisitItemState.pending:
      default:
        return Colors.grey.shade200;
    }
  }

  Color _textColor() {
    switch (state) {
      case VisitItemState.done:
        return Colors.green.shade800;
      case VisitItemState.inVisit:
        return Colors.blue.shade800;
      case VisitItemState.enRoute:
      case VisitItemState.onSite:
        return Colors.orange.shade800;
      case VisitItemState.cancelled:
        return Colors.grey.shade700;
      case VisitItemState.pending:
      default:
        return Colors.grey.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        state.label,
        style: TextStyle(fontSize: 11, color: _textColor()),
      ),
    );
  }
}

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:42 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: VisitPlanScreen respuestas dialog data]
class _RespuestasDialogData {
  _RespuestasDialogData({
    required this.cuestionarioNombre,
    required this.respuestas,
  });

  final String cuestionarioNombre;
  final List<RespuestaPregunta> respuestas;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (onRetry != null)
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }
}
