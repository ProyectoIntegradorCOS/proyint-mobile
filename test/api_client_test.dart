import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'dart:convert';
import 'dart:io';
import 'package:get_it/get_it.dart';

import 'package:flutter_application_1/services/api_client.dart';
import 'package:flutter_application_1/services/auth_service.dart';

// Generar mocks: flutter pub run build_runner build
@GenerateMocks([http.Client, AuthService])
import 'api_client_test.mocks.dart';

void main() {
  late MockClient mockHttpClient;
  late MockAuthService mockAuthService;
  late ApiClient apiClient;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GetIt.I.allowReassignment = true;
  });

  setUp(() {
    mockHttpClient = MockClient();
    mockAuthService = MockAuthService();

    // Setup GetIt for the test
    GetIt.I.reset();
    GetIt.I.registerSingleton<AuthService>(mockAuthService);

    apiClient = ApiClient(client: mockHttpClient, authService: mockAuthService);
  });

  tearDown(() {
    GetIt.I.reset();
  });

  group('ApiClient Core Tests', () {
    test('getJsonHeaders inyecta Authorization si hay token en sesion', () async {
      final session = UserSession(
        uid: '123',
        usuario: 'test',
        token: 'valid-token',
        nombre: 'test',
      );
      when(mockAuthService.currentSession).thenReturn(session);
      await apiClient.updateAuthToken('valid-token');

      final headers = apiClient.getJsonHeaders();

      expect(headers['Content-Type'], 'application/json');
      expect(headers['Authorization'], 'Bearer valid-token');
      expect(headers['X-Trace-Id'], isNotNull);
    });

    test('getJsonHeaders NO inyecta Authorization si NO hay sesion', () {
      when(mockAuthService.currentSession).thenReturn(null);

      final headers = apiClient.getJsonHeaders();

      expect(headers['Content-Type'], 'application/json');
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('sendWithRetry retorna respuesta exitosa al primer intento', () async {
      when(mockAuthService.ensureValidToken())
          .thenAnswer((_) async => 'valid-token');
      when(mockHttpClient.get(Uri.parse('http://test.com')))
          .thenAnswer((_) async => http.Response('{"ok":true}', 200));

      final response = await apiClient.sendWithRetry(
          () => mockHttpClient.get(Uri.parse('http://test.com')));

      expect(response.statusCode, 200);
      verify(mockHttpClient.get(Uri.parse('http://test.com'))).called(1);
    });

    test('sendWithRetry renueva token y reintenta si recibe 401', () async {
      // Configuramos el cliente HTTP para devolver 401 en el primer llamado y 200 en el segundo
      int callCount = 0;
      when(mockHttpClient.get(Uri.parse('http://test.com/secure'))).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('Unauthorized', 401);
        }
        return http.Response('{"data":"ok"}', 200);
      });

      // Aseguramos que ensureValidToken se invoque simulando una renovacion exitosa
      when(mockAuthService.ensureValidToken())
          .thenAnswer((_) async => 'new-token');
      when(mockAuthService.renewToken())
          .thenAnswer((_) async => true);
      when(mockAuthService.attemptReauthIfRemembered())
          .thenAnswer((_) async => false);
      when(mockAuthService.signOut())
          .thenAnswer((_) async {});
      when(mockAuthService.currentSession)
          .thenReturn(UserSession(uid: '1', usuario: 'test', token: 'new-token', nombre: 'Test'));

      final response = await apiClient.sendWithRetry(
          () => mockHttpClient.get(Uri.parse('http://test.com/secure')));

      expect(response.statusCode, 200);
      expect(response.body, '{"data":"ok"}');
      
      // Verificamos el flujo
      verify(mockHttpClient.get(Uri.parse('http://test.com/secure'))).called(2);
      verify(mockAuthService.ensureValidToken()).called(1);
    });

    test('sendWithRetry propaga el error de red cuando Http Request tira Exception', () async {
      when(mockAuthService.ensureValidToken())
          .thenAnswer((_) async => 'valid-token');
      when(mockHttpClient.get(Uri.parse('http://test.com/net_error')))
          .thenThrow(Exception('No connection'));

      expect(
        apiClient.sendWithRetry(() => mockHttpClient.get(Uri.parse('http://test.com/net_error'))),
        throwsA(isA<Exception>()),
      );
    });
  });
}
