import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/cuestionario.dart';

class FormRepository {
  final Future<http.Response> Function(Future<http.Response> Function()) sendWithRetry;
  final Map<String, String> Function() getJsonHeaders;

  FormRepository({
    required this.sendWithRetry,
    required this.getJsonHeaders,
  });

  Uri _buildUri(String path) {
    return Uri.parse('${Constants.apiBaseUrl}$path');
  }

  Future<Cuestionario?> fetchCuestionarioActivo() async {
    final uri = _buildUri('/cuestionarios/activo');
    final response = await sendWithRetry(
      () => http.get(uri, headers: getJsonHeaders()),
    );
    if (response.statusCode == 204) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('Error obteniendo cuestionario (${response.statusCode}): ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Cuestionario.fromJson(data);
  }

  Future<List<Pregunta>> fetchPreguntasPorCuestionario(int idCuestionario) async {
    final uri = _buildUri('/preguntas/cuestionario/$idCuestionario');
    final response = await sendWithRetry(
      () => http.get(uri, headers: getJsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw Exception('Error obteniendo preguntas (${response.statusCode}): ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => Pregunta.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> registrarRespuestas(List<RespuestaPayload> respuestas) async {
    for (final respuesta in respuestas) {
      final uri = _buildUri('/respuestas');
      final response = await sendWithRetry(
        () => http.post(
          uri,
          headers: getJsonHeaders(),
          body: jsonEncode(respuesta.toJson()),
        ),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Error guardando respuestas (${response.statusCode}): ${response.body}');
      }
    }
  }

  Future<List<RespuestaPregunta>> fetchRespuestasCuestionario({
    required int idCuestionario,
    required int idPersona,
  }) async {
    final uri = _buildUri('/respuestas/cuestionario/$idCuestionario')
        .replace(queryParameters: {'idPersona': idPersona.toString()});
    final response = await sendWithRetry(
      () => http.get(uri, headers: getJsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw Exception('Error obteniendo respuestas (${response.statusCode}): ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => RespuestaPregunta.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<RespuestaPregunta>> fetchRespuestasPorItem({
    required int idItem,
  }) async {
    final uri = _buildUri('/respuestas/visit-item/$idItem');
    final response = await sendWithRetry(
      () => http.get(uri, headers: getJsonHeaders()),
    );
    if (response.statusCode != 200) {
      throw Exception('Error obteniendo respuestas (${response.statusCode}): ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => RespuestaPregunta.fromJson(e as Map<String, dynamic>)).toList();
  }
}
