import 'package:get_it/get_it.dart';
import 'package:flutter/services.dart';
import '../utils/logger.dart';
import 'telemetry_log_service.dart';
import 'dart:async';

class ScreenStateService {
  ScreenStateService._();

  static final ScreenStateService instance = ScreenStateService._();
  static const MethodChannel _channel =
      MethodChannel('pe.gob.onp.thaqhiri/screen_state');

  bool _started = false;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  Stream<String> get stream => _controller.stream;

  void start() {
    if (_started) return;
    _started = true;
    _flushPendingEvents();
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'screen_off':
          _handleEvent('screen_off');
          break;
        case 'screen_on':
          _handleEvent('screen_on');
          break;
        default:
          break;
      }
    });
  }

  Future<void> _flushPendingEvents() async {
    try {
      final events =
          await _channel.invokeMethod<List<dynamic>>('getPendingEvents');
      if (events == null) return;
      for (final e in events) {
        _handleEvent(e.toString(), pending: true);
      }
    } catch (_) {}
  }

  void _handleEvent(String event, {bool pending = false}) {
    final label = event == 'screen_off'
        ? 'Pantalla apagada'
        : event == 'screen_on'
            ? 'Pantalla encendida'
            : 'Estado pantalla: $event';
    logDebug('$label${pending ? ' (pendiente)' : ''}');
    unawaited(
      GetIt.I<TelemetryLogService>().log(
        pending ? '$label (pendiente)' : label,
      ),
    );
    _controller.add(event);
  }
}
