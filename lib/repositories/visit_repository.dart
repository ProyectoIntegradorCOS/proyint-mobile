import 'package:get_it/get_it.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/visit_plan.dart';
import '../services/telemetry_log_service.dart';
import '../utils/logger.dart';

class VisitRepository {
  final Future<http.Response> Function(Future<http.Response> Function()) sendWithRetry;
  final Map<String, String> Function() getJsonHeaders;
  final http.Client client;
  final Duration timeout;

  VisitRepository({
    required this.sendWithRetry,
    required this.getJsonHeaders,
    required this.client,
    required this.timeout,
  });

  Uri _buildUri(String path) {
    return Uri.parse('${Constants.apiBaseUrl}$path');
  }

  Future<VisitPlan> fetchVisitPlanForMe() async {
    final uri = _buildUri('/visit-plans/mine');
    logDebug('fetchVisitPlanForMe inicio', details: 'url=$uri');
    
    Future<http.Response> _doGet() => client.get(uri, headers: getJsonHeaders());

    http.Response response;
    try {
      response = await sendWithRetry(_doGet);
    } catch (e) {
      logError('fetchVisitPlanForMe fallo red/401', error: e);
      await Future<void>.delayed(const Duration(seconds: 1));
      response = await client.get(uri, headers: getJsonHeaders()).timeout(timeout);
    }

    logDebug('fetchVisitPlanForMe respuesta',
        details: 'status=${response.statusCode} len=${response.body.length}');

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitPlan.fromJson(json);
    }
    if (response.statusCode == 404) {
      throw Exception('No tienes un plan de visitas asignado.');
    }
    throw Exception('Error obteniendo plan (${response.statusCode}): ${response.body}');
  }

  Future<VisitPlan> reorderVisitItems({
    required int planId,
    required List<int> itemIds,
  }) async {
    final uri = _buildUri('/visit-plans/$planId/items/reorder');
    final response = await sendWithRetry(() {
      return client.patch(
        uri,
        headers: getJsonHeaders(),
        body: jsonEncode({'itemIds': itemIds}),
      );
    });
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitPlan.fromJson(json);
    }
    throw Exception('Error reordenando visitas (${response.statusCode}): ${response.body}');
  }

  Future<VisitItem> updateVisitState({
    required int itemId,
    required VisitItemState newState,
    double? startLatitude,
    double? startLongitude,
    double? eventLatitude,
    double? eventLongitude,
    required String source,
  }) async {
    final uri = _buildUri('/visit-plans/items/$itemId/state');
    final payload = {
      'newState': newState.apiValue,
      if (startLatitude != null) 'startLatitude': startLatitude,
      if (startLongitude != null) 'startLongitude': startLongitude,
      if (eventLatitude != null) 'eventLatitude': eventLatitude,
      if (eventLongitude != null) 'eventLongitude': eventLongitude,
    };
    try {
      await GetIt.I<TelemetryLogService>().log(
        'updateVisitState: origen=$source itemId=$itemId payload=$payload',
      );
    } catch (_) {}
    
    final response = await sendWithRetry(() {
      return client.patch(
        uri,
        headers: getJsonHeaders(),
        body: jsonEncode(payload),
      );
    });
    
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitItem.fromJson(json);
    }
    throw Exception('No se pudo actualizar el estado (${response.statusCode}): ${response.body}');
  }

  Future<bool> checkBackendAvailable({
    Duration timeoutLimit = const Duration(seconds: 5),
  }) async {
    try {
      final resp = await client
          .get(_buildUri('/health/db'), headers: getJsonHeaders())
          .timeout(timeoutLimit);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<VisitItem> completeVisit({
    required int itemId,
    bool? complex,
    bool? foundProblem,
    String? problemNote,
    String? otherInfo,
    double? eventLatitude,
    double? eventLongitude,
  }) async {
    final uri = _buildUri('/visit-plans/items/$itemId/complete');
    final response = await sendWithRetry(() {
      return client.post(
        uri,
        headers: getJsonHeaders(),
        body: jsonEncode({
          'complex': complex,
          'foundProblem': foundProblem,
          if (problemNote != null && problemNote.isNotEmpty) 'problemNote': problemNote,
          if (otherInfo != null && otherInfo.isNotEmpty) 'otherInfo': otherInfo,
          if (eventLatitude != null) 'eventLatitude': eventLatitude,
          if (eventLongitude != null) 'eventLongitude': eventLongitude,
        }),
      );
    });
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitItem.fromJson(json);
    }
    throw Exception('No se pudo completar la visita (${response.statusCode}): ${response.body}');
  }
}
