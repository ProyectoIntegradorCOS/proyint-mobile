import 'package:get_it/get_it.dart';
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 13:45 UTC-5 (Lima)][desc: Widget extraído para configuración de mapa][obj: MapSettingsSheet]
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../controllers/visit_controller.dart';
import '../../controllers/tracking_controller.dart';
import 'dart:async';
import '../../../../services/telemetry_log_service.dart';
import '../../../../services/background_schedule_manager.dart';

class MapSettingsSheet extends StatefulWidget {
  final VisitController visitController;
  final TrackingController trackingController;

  const MapSettingsSheet({
    Key? key,
    required this.visitController,
    required this.trackingController,
  }) : super(key: key);

  @override
  State<MapSettingsSheet> createState() => _MapSettingsSheetState();
}

class _MapSettingsSheetState extends State<MapSettingsSheet> {
  late TextEditingController _radiusController;
  late TextEditingController _dwellController;
  late TextEditingController _stillIntervalController;
  late TextEditingController _stillDistanceController;
  late TextEditingController _captureIntervalController;
  late TextEditingController _captureDistanceController;
  late TextEditingController _maxStaleController;
  bool _nativeAlwaysOn = false;
  late TextEditingController _forceAcceptController;
  late TextEditingController _maxAccuracyController;
  bool _filtersEnabled = true;

  @override
  void initState() {
    super.initState();
    _radiusController = TextEditingController(
      text: widget.visitController.arrivalRadiusMeters.toStringAsFixed(0),
    );
    _dwellController = TextEditingController(
      text: widget.visitController.dwellDuration.inMinutes.toString(),
    );
    _stillIntervalController = TextEditingController(
      text: widget.trackingController.stillIntervalSeconds.toString(),
    );
    _stillDistanceController = TextEditingController(
      text: widget.trackingController.stillMinDistanceMeters.toStringAsFixed(0),
    );
    _captureIntervalController = TextEditingController(
      text: widget.trackingController.captureIntervalSeconds.toString(),
    );
    _captureDistanceController = TextEditingController(
      text: widget.trackingController.captureDistanceMeters.toString(),
    );
    _maxStaleController = TextEditingController(
      text: widget.trackingController.maxStaleSeconds.toString(),
    );
    _nativeAlwaysOn = widget.trackingController.nativeAlwaysOn;
    _forceAcceptController = TextEditingController(
      text: widget.trackingController.forceAcceptAfterSeconds.toString(),
    );
    _maxAccuracyController = TextEditingController(
      text: widget.trackingController.maxAccuracyMeters.toStringAsFixed(0),
    );
    _filtersEnabled = widget.trackingController.filtersEnabled;
    _loadTrackingFilterPrefs();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    _dwellController.dispose();
    _stillIntervalController.dispose();
    _stillDistanceController.dispose();
    _captureIntervalController.dispose();
    _captureDistanceController.dispose();
    _maxStaleController.dispose();
    _forceAcceptController.dispose();
    _maxAccuracyController.dispose();
    super.dispose();
  }

  Future<void> _loadTrackingFilterPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stillInterval = prefs.getInt('tracking_still_interval_s');
      final stillDistance = prefs.getDouble('tracking_still_min_dist_m');
      final captureInterval = prefs.getInt('tracking_capture_interval_s');
      final captureDistance = prefs.getInt('tracking_capture_distance_m');
      final maxStale = prefs.getInt('tracking_max_stale_s');
      final nativeAlwaysOn = prefs.getBool('tracking_native_always_on');
      final forceAccept = prefs.getInt('tracking_force_accept_s');
      final maxAccuracy = prefs.getDouble('tracking_max_accuracy_m');
      final filtersEnabled = prefs.getBool('tracking_filters_enabled');
      if (!mounted) return;
      if (stillInterval != null) {
        _stillIntervalController.text = stillInterval.toString();
      }
      if (stillDistance != null) {
        _stillDistanceController.text = stillDistance.toStringAsFixed(0);
      }
      if (captureInterval != null) {
        _captureIntervalController.text = captureInterval.toString();
      }
      if (captureDistance != null) {
        _captureDistanceController.text = captureDistance.toString();
      }
      if (maxStale != null) {
        _maxStaleController.text = maxStale.toString();
      }
      if (nativeAlwaysOn != null) {
        _nativeAlwaysOn = nativeAlwaysOn;
      }
      if (forceAccept != null) {
        _forceAcceptController.text = forceAccept.toString();
      }
      if (maxAccuracy != null) {
        _maxAccuracyController.text = maxAccuracy.toStringAsFixed(0);
      }
      if (filtersEnabled != null) {
        _filtersEnabled = filtersEnabled;
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    final r = double.tryParse(_radiusController.text.trim());
    final m = int.tryParse(_dwellController.text.trim());
    final stillInterval = int.tryParse(_stillIntervalController.text.trim());
    final stillDistance = double.tryParse(_stillDistanceController.text.trim());
    final captureInterval = int.tryParse(_captureIntervalController.text.trim());
    final captureDistance = int.tryParse(_captureDistanceController.text.trim());
    final maxStale = int.tryParse(_maxStaleController.text.trim());
    final forceAccept = int.tryParse(_forceAcceptController.text.trim());
    final maxAccuracy = double.tryParse(_maxAccuracyController.text.trim());
    if (r == null || r <= 0 ||
        m == null || m <= 0 ||
        stillInterval == null || stillInterval <= 0 ||
        stillDistance == null || stillDistance <= 0 ||
        captureInterval == null || captureInterval <= 0 ||
        captureDistance == null || captureDistance <= 0 ||
        maxStale == null || maxStale <= 0 ||
        forceAccept == null || forceAccept <= 0 ||
        maxAccuracy == null || maxAccuracy <= 0) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valores no válidos')),
      );
      return;
    }
    final clampedRadius = r.clamp(10.0, 500.0).toDouble();
    final clampedMinutes = m.clamp(1, 60);
    final clampedStillInterval = stillInterval.clamp(5, 600);
    final clampedStillDistance = stillDistance.clamp(1.0, 100.0);
    final clampedCaptureInterval = captureInterval.clamp(1, 120);
    final clampedCaptureDistance = captureDistance.clamp(1, 100);
    final clampedMaxStale = maxStale.clamp(60, 43200);
    final clampedForceAccept = forceAccept.clamp(10, 900);
    final clampedMaxAccuracy = maxAccuracy.clamp(5.0, 100.0);
    final clampedDuration = Duration(minutes: clampedMinutes);

    widget.visitController.configureArrivalDetection(
      radiusMeters: clampedRadius,
      dwellDuration: clampedDuration,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('arrival_radius_m', clampedRadius);
    await prefs.setInt('dwell_minutes', clampedMinutes);
    await prefs.setInt('tracking_still_interval_s', clampedStillInterval);
    await prefs.setDouble('tracking_still_min_dist_m', clampedStillDistance);
    await prefs.setInt('tracking_capture_interval_s', clampedCaptureInterval);
    await prefs.setInt('tracking_capture_distance_m', clampedCaptureDistance);
    await prefs.setInt('tracking_max_stale_s', clampedMaxStale);
    await prefs.setBool('tracking_native_always_on', _nativeAlwaysOn);
    await prefs.setInt('tracking_force_accept_s', clampedForceAccept);
    await prefs.setDouble('tracking_max_accuracy_m', clampedMaxAccuracy);
    await prefs.setBool('tracking_filters_enabled', _filtersEnabled);

    widget.trackingController.updateTrackingFilters(
      stillIntervalSeconds: clampedStillInterval,
      stillMinDistanceMeters: clampedStillDistance,
      captureIntervalSeconds: clampedCaptureInterval,
      captureDistanceMeters: clampedCaptureDistance,
      maxStaleSeconds: clampedMaxStale,
      nativeAlwaysOn: _nativeAlwaysOn,
      forceAcceptSeconds: clampedForceAccept,
      maxAccuracyMeters: clampedMaxAccuracy,
      filtersEnabled: _filtersEnabled,
    );

    // Aplica de inmediato el modo de tracking nativo continuo si el tracking está activo.
    if (widget.trackingController.isTracking) {
      if (_nativeAlwaysOn) {
        await BackgroundScheduleManager.startNativeTracking();
        unawaited(
          GetIt.I<TelemetryLogService>().log(
            'Tracking nativo continuo: inicio (ajustes)',
          ),
        );
      } else {
        await BackgroundScheduleManager.stopNativeTracking();
        unawaited(
          GetIt.I<TelemetryLogService>().log(
            'Tracking nativo continuo: fin (ajustes)',
          ),
        );
      }
    }

    unawaited(
      GetIt.I<TelemetryLogService>().log(
        'Configuracion guardada: native_always_on=${_nativeAlwaysOn ? 'SI' : 'NO'} radio_llegada_m=$clampedRadius permanencia_min=$clampedMinutes capture_int_s=$clampedCaptureInterval capture_dist_m=$clampedCaptureDistance stale_s=$clampedMaxStale accuracy_max_m=$clampedMaxAccuracy filtros_app=${_filtersEnabled ? 'ON' : 'OFF'}',
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración guardada')),
    );
  }


  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajustes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _radiusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Radio de llegada (m)',
                  helperText: 'Recomendado 50–100 m',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dwellController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiempo de espera (min)',
                  helperText: 'Recomendado 3–10 min',
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Filtros de tracking',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _captureIntervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Intervalo de captura (s)',
                  helperText: 'Tiempo mínimo entre puntos (recomendado 10 s)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _captureDistanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Distancia mínima de captura (m)',
                  helperText:
                      'Movimiento mínimo para nuevo punto (recomendado 10 m)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _maxStaleController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Antigüedad máxima (s)',
                  helperText:
                      'Puntos más antiguos se descartan (recomendado 7200 s)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _stillIntervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Intervalo en quieto (s)',
                  helperText: 'Recomendado 30–120 s',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _stillDistanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Distancia mínima en quieto (m)',
                  helperText: 'Recomendado 5–20 m',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _forceAcceptController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Forzar punto si no llega nada (s)',
                  helperText: 'Recomendado 300–600 s',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _maxAccuracyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Accuracy máximo (m)',
                  helperText: 'Recomendado 20 m',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _filtersEnabled,
                onChanged: (v) {
                  setState(() => _filtersEnabled = v);
                  unawaited(
                    GetIt.I<TelemetryLogService>().log(
                      'Toggle filtros en app: ${v ? 'ON' : 'OFF'}',
                    ),
                  );
                },
                title: const Text('Aplicar filtros en app'),
                subtitle: Text(
                  _filtersEnabled
                      ? 'ON: El app filtra puntos antes de enviarlos.'
                      : 'OFF: Solo se filtra en backend.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
              value: _nativeAlwaysOn,
              onChanged: (v) {
                setState(() => _nativeAlwaysOn = v);
                unawaited(
                  GetIt.I<TelemetryLogService>().log(
                    'Toggle nativo continuo: ${v ? 'ON' : 'OFF'}',
                  ),
                );
              },
              title: const Text('Tracking nativo continuo'),
              subtitle: Text(
                _nativeAlwaysOn
                    ? 'ON: Servicio nativo siempre activo. Captura estable, mayor consumo.'
                    : 'OFF: Nativo solo en background/pantalla apagada.',
              ),
            ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                    ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
