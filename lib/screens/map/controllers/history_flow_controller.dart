// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:55 UTC-5 (Lima)][desc: Corrige controlador de flujo de historial con API correcta][obj: HistoryFlowController]
import 'dart:async';
import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../widgets/sheets/history_details_sheet.dart';
import 'map_screen_controller.dart';

class HistoryFlowController {
  final MapScreenController stateController;
  final ApiService apiService;
  final Function(String) onError;
  final String firebaseUid;

  HistoryFlowController({
    required this.stateController,
    required this.apiService,
    required this.onError,
    required this.firebaseUid,
  });

  Future<void> selectAndLoadHistory(BuildContext context) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 15:30 UTC-5 (Lima)][desc: Unifica selección de historial (día único vs rango) en un solo flujo][obj: HistoryFlowController.selectAndLoadHistory]
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ver Historial'),
        content: const Text('¿Qué tipo de historial deseas consultar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'date'),
            child: const Text('Un solo día'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'range'),
            child: const Text('Rango de fechas'),
          ),
        ],
      ),
    );

    if (choice == 'date') {
      await _selectAndLoadHistoryByDate(context);
    } else if (choice == 'range') {
      await _selectAndLoadHistoryByRange(context);
    }
  }

  Future<void> _selectAndLoadHistoryByDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
      helpText: 'Selecciona una fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      locale: const Locale('es', 'PE'),
    );

    if (picked != null) {
      final range = DateTimeRange(start: picked, end: picked);
      await loadHistoryForRange(range);
      if (context.mounted && stateController.historyPoints.isNotEmpty) {
        showHistoryDetails(context);
      }
    }
  }

  Future<void> _selectAndLoadHistoryByRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 1)),
        end: DateTime.now(),
      ),
      helpText: 'Selecciona un rango de fechas',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      locale: const Locale('es', 'PE'),
    );

    if (picked != null) {
      await loadHistoryForRange(picked);

      if (context.mounted && stateController.historyPoints.isNotEmpty) {
        showHistoryDetails(context);
      }
    }
  }

  Future<void> loadHistoryForRange(DateTimeRange range) async {
    stateController.setShowingHistory(true);
    stateController.resetHistory();
    stateController.setLoadingMoreHistory(true);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Guarda rango seleccionado para mostrarlo en overlay][obj: HistoryFlowController.loadHistoryForRange setLastHistoryRange]
    stateController.setLastHistoryRange(range);

    final startUtc = DateTime.utc(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final endUtc = DateTime.utc(
      range.end.year,
      range.end.month,
      range.end.day,
    ).add(const Duration(days: 1));

    try {
      // Usamos fetchHistory que devuelve HistoryResponse con totalDistanceKm
      final history = await apiService.fetchHistory(
        firebaseUid: firebaseUid,
        start: startUtc,
        end: endUtc,
      );

      final sortedPoints = List.of(history.points)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 14:08 UTC-5 (Lima)][desc: Ordena puntos de historial por timestamp para listado y ruta][obj: HistoryFlowController.loadHistoryForRange sort]
      stateController.setHistoryPoints(sortedPoints);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Actualiza distancia total del overlay de historial][obj: HistoryFlowController.loadHistoryForRange totalDistanceKm]
      stateController.setTotalDistance(history.totalDistanceKm);
      
      stateController.setHasMoreHistory(false); // No pagination for now in this flow

      if (history.points.isEmpty) {
        onError('No hay historial para este rango de fechas');
      }
    } catch (e) {
      onError('Error al cargar historial: $e');
    } finally {
      stateController.setLoadingMoreHistory(false);
    }
  }

  Future<void> loadMoreHistory() async {
    if (stateController.isLoadingMoreHistory || !stateController.hasMoreHistory) return;

    stateController.setLoadingMoreHistory(true);
    // En una implementación real con paginación, aquí cargarías más datos
    await Future.delayed(const Duration(milliseconds: 500));
    stateController.setHasMoreHistory(false);
    stateController.setLoadingMoreHistory(false);
  }

  void showHistoryDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 14:27 UTC-5 (Lima)][desc: Usa fondo opaco para evitar translucidez del detalle de historial][obj: HistoryFlowController.showHistoryDetails]
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => HistoryDetailsSheet(
        points: stateController.historyPoints,
        onPointSelected: (point) {
          // Callback para seleccionar punto en el mapa
          Navigator.of(ctx).pop();
        },
        onLoadMore: stateController.hasMoreHistory ? loadMoreHistory : null,
        isLoadingMore: stateController.isLoadingMoreHistory,
      ),
    );
  }
}
