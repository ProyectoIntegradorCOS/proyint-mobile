import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const secureStoreChannel = MethodChannel('pe.gob.onp.thaqhiri/secure_store');
  final secureStorage = <String, String?>{};

  group('AuthService', () {
    setUp(() async {
      secureStorage.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
            final key = call.arguments['key'] as String?;
            switch (call.method) {
              case 'read':
                if (key == null) return null;
                return secureStorage[key];
              case 'write':
                if (key == null) return null;
                secureStorage[key] = call.arguments['value'] as String?;
                return null;
              case 'delete':
                if (key != null) secureStorage.remove(key);
                return null;
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStoreChannel, (call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStoreChannel, null);
    });

    test('signOut limpia sesion local pero mantiene tracking_uid', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_usuario': 'usuario.demo',
        'auth_nombre': 'Usuario Demo',
        'auth_uid': 'auth-123',
        'tracking_uid': 'tracking-999',
        'bg_flush_last_at': '2026-03-12T10:00:00-05:00',
        'bg_flush_last_status': 'ok',
      });

      final service = AuthService();

      await service.signOut();

      final prefs = await SharedPreferences.getInstance();
      expect(service.currentSession, isNull);
      expect(prefs.getString('auth_usuario'), isNull);
      expect(prefs.getString('auth_nombre'), isNull);
      expect(prefs.getString('auth_uid'), isNull);
      expect(prefs.getString('tracking_uid'), 'tracking-999');
      expect(prefs.getString('bg_flush_last_at'), isNull);
      expect(prefs.getString('bg_flush_last_status'), isNull);
    });

    test(
      'signOutSaa sin token devuelve resultado 3 y limpia sesion local',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'auth_usuario': 'usuario.demo',
          'auth_nombre': 'Usuario Demo',
          'auth_uid': 'auth-123',
          'tracking_uid': 'tracking-999',
        });

        final service = AuthService();

        final result = await service.signOutSaa();

        final prefs = await SharedPreferences.getInstance();
        expect(result.resultado, '3');
        expect(result.success, isFalse);
        expect(prefs.getString('auth_usuario'), isNull);
        expect(prefs.getString('auth_nombre'), isNull);
        expect(prefs.getString('auth_uid'), isNull);
        expect(prefs.getString('tracking_uid'), 'tracking-999');
      },
    );

    test('restoreSession normaliza token envuelto en JSON', () async {
      const jwt =
          'eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiI0MTkzMCIsIlVzdWFyaW8iOiJjb3JtZW5vcyIsIk5vbWJyZSI6IkNhcmxvcyJ9.firma';
      secureStorage['auth_token'] = '{"token":"$jwt"}';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_usuario': 'cormenos',
        'auth_nombre': 'Carlos',
      });

      final service = AuthService();

      await service.restoreSession();

      expect(service.currentSession, isNotNull);
      expect(service.currentSession!.token, jwt);
      expect(service.currentSession!.uid, '41930');
      expect(service.currentSession!.usuario, 'cormenos');
    });
  });
}
