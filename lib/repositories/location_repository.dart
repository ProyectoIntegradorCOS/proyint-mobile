import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/location_point.dart';
import '../utils/logger.dart';
import '../utils/lima_time.dart';

class LocationRepository {
  final Future<http.Response> Function(Future<http.Response> Function()) sendWithRetry;
  final Map<String, String> Function() getJsonHeaders;
  final String Function() getNewTraceId;
  final Future<void> Function({
    required String action,
    required String screen,
    String status,
    int? durationMs,
    String? version,
  }) sendMetric;

  LocationRepository({
    required this.sendWithRetry,
    required this.getJsonHeaders,
    required this.getNewTraceId,
    required this.sendMetric,
  });

  Uri _buildUri(String path) {
    return Uri.parse('${Constants.apiBaseUrl}$path');
  }

  Future<void> sendLocation({
    required String firebaseUid,
    required LocationPoint point,
    int? batteryLevel,
    String? activityType,
  }) async {
    final startedAt = DateTime.now();
    final traceId = getNewTraceId();
    logDebug('Enviando ubicación al backend',
        details: 'uid=$firebaseUid lat=${point.latitude} lng=${point.longitude} ts=${point.timestamp.toIso8601String()}');
    logInfo('API sendLocation -> POST /locations',
        details: 'traceId=$traceId uid=$firebaseUid ts=${toLimaIsoString(point.timestamp)}');
    logDebug('API sendLocation -> POST /locations',
        details: 'traceId=$traceId uid=$firebaseUid ts=${toLimaIsoString(point.timestamp)}');
        
    final payload = {
      'saaSubject': firebaseUid,
      'latitude': point.latitude,
      'longitude': point.longitude,
      'timestamp': toLimaIsoString(point.timestamp),
      if (point.accuracy != null) 'accuracy': point.accuracy,
      if (point.altitude != null) 'altitude': point.altitude,
      if (point.speed != null) 'speed': point.speed,
      if (point.heading != null) 'heading': point.heading,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
      if (activityType != null) 'activityType': activityType,
    };

    final response = await sendWithRetry(() {
      return http.post(
        _buildUri('/locations'),
        headers: {...getJsonHeaders(), 'X-Trace-Id': traceId},
        body: jsonEncode(payload),
      );
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      logInfo('API sendLocation OK', details: 'traceId=$traceId status=${response.statusCode}');
      logDebug('Ubicación enviada correctamente');
      await sendMetric(
        action: 'ubicacion_envio',
        screen: 'geolocalizacion',
        status: 'success',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      return;
    }

    logError('API sendLocation FAIL',
        error: 'traceId=$traceId status=${response.statusCode} body=${response.body}');
    await sendMetric(
      action: 'ubicacion_envio',
      screen: 'geolocalizacion',
      status: 'error',
    );
    throw Exception('Error enviando ubicación (${response.statusCode}): ${response.body}');
  }

  Future<void> sendLocationBatch(List<Map<String, dynamic>> locations) async {
    if (locations.isEmpty) return;

    final startedAt = DateTime.now();
    final traceId = getNewTraceId();
    logDebug('Enviando batch de ${locations.length} ubicaciones');
    
    final normalizedLocations = locations.map((m) {
      final out = Map<String, dynamic>.from(m);
      out.remove('id');
      out.remove('timestamp_epoch_ms');
      final bl = out['batteryLevel'];
      if (bl is num) {
        out['batteryLevel'] = bl.round();
      }
      return out;
    }).toList();
    
    final payload = {'locations': normalizedLocations};
    final firstTs = normalizedLocations.first['timestamp']?.toString();
    final lastTs = normalizedLocations.last['timestamp']?.toString();
    logInfo('API sendLocationBatch -> POST /locations/batch',
        details: 'traceId=$traceId count=${normalizedLocations.length} firstTs=$firstTs lastTs=$lastTs');
    logDebug('API sendLocationBatch -> POST /locations/batch',
        details: 'traceId=$traceId count=${normalizedLocations.length} firstTs=$firstTs lastTs=$lastTs');

    final response = await sendWithRetry(() {
      return http.post(
        _buildUri('/locations/batch'),
        headers: {...getJsonHeaders(), 'X-Trace-Id': traceId},
        body: jsonEncode(payload),
      );
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      logInfo('API sendLocationBatch OK',
          details: 'traceId=$traceId status=${response.statusCode} body=${response.body}');
      logDebug('Batch enviado correctamente');
      await sendMetric(
        action: 'ubicacion_batch_envio',
        screen: 'geolocalizacion',
        status: 'success',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      return;
    }

    logError('API sendLocationBatch FAIL',
        error: 'traceId=$traceId status=${response.statusCode} body=${response.body}');
    await sendMetric(
      action: 'ubicacion_batch_envio',
      screen: 'geolocalizacion',
      status: 'error',
    );
    throw Exception('Error enviando batch de ubicaciones (${response.statusCode}): ${response.body}');
  }
}
