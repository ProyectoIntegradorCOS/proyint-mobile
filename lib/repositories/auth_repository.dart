import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';
import '../utils/logger.dart';

class AuthRepository {
  /// Intenta obtener un token del backend
  Future<http.Response> postAuthToken(Map<String, dynamic> payload) async {
    final url = Uri.parse('${Constants.apiBaseUrl}/auth/token');
    return await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
  }
}
