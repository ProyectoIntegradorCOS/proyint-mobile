import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/services/api_service.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/models/location_point.dart';

class _FakeAuthService extends AuthService {
  @override
  Future<String?> ensureValidToken({
    Duration minTtl = const Duration(minutes: 5),
  }) async => null;

  @override
  Future<bool> renewToken() async => false;

  @override
  Future<bool> attemptReauthIfRemembered() async => false;

  @override
  Future<void> signOut() async {}
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(fileInput: 'URL_BACKEND=http://example.com/api');
    GetIt.I.allowReassignment = true;
  });

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<AuthService>(_FakeAuthService());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('ApiService', () {
    test('saveUserProfile posts payload and handles 201', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('/users'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['saaSubject'], 'abc');
        expect(body['usuario'], 'user');
        expect(body['nombre'], 'Nombre');
        expect(body['estado'], 1);
        return http.Response(jsonEncode({
          'id': 1,
          'saaSubject': 'abc',
          'usuario': 'user',
          'nombre': 'Nombre',
          'estado': 1,
          'horarioId': 1,
          'equipoId': 1
        }), 201);
      });
      final api = ApiService(client: client);
      await api.saveUserProfile(
        saaSubject: 'abc',
        usuario: 'user',
        nombre: 'Nombre',
        estado: 1,
        horarioId: 1,
        equipoId: 1,
        usuarioSesion: 'user',
      );
    });

    test('fetchHistory parses response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, contains('/locations/history'));
        final payload = {
          'saaSubject': 'abc',
          'start': DateTime.now().toUtc().toIso8601String(),
          'end': DateTime.now().toUtc().toIso8601String(),
          'totalDistanceKm': 1.23,
          'points': [
            {
              'latitude': -12.05,
              'longitude': -77.05,
              'timestamp': DateTime.now().toUtc().toIso8601String()
            }
          ]
        };
        return http.Response(jsonEncode(payload), 200);
      });
      final api = ApiService(client: client);
      final res = await api.fetchHistory(
        firebaseUid: 'abc',
        start: DateTime.now().toUtc(),
        end: DateTime.now().toUtc(),
      );
      expect(res.totalDistanceKm, 1.23);
      expect(res.points.length, 1);
    });

    test('sendLocation sends correct payload', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('/locations'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['saaSubject'], 'abc');
        expect(body['latitude'], -12.0);
        return http.Response('{}', 201);
      });
      final api = ApiService(client: client);
      await api.sendLocation(
        firebaseUid: 'abc',
        point: LocationPoint(
          latitude: -12.0,
          longitude: -77.0,
          timestamp: DateTime.now(),
        ),
      );
    });
  });
}
