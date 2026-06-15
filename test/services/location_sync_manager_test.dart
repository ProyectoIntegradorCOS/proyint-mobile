import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_application_1/services/api_service.dart';
import 'package:flutter_application_1/services/location_sync_manager.dart';
import 'package:flutter_application_1/services/pending_location_store.dart';
import 'package:flutter_application_1/models/location_point.dart';
import 'package:flutter_application_1/models/pending_location.dart';

import 'location_sync_manager_test.mocks.dart';

@GenerateMocks([ApiService, PendingLocationStore])
void main() {
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Ajusta tests al batching por usuario (countForSubject/getBatchForSubject) y mocks regenerados][obj: location_sync_manager_test]
  late MockApiService mockApiService;
  late MockPendingLocationStore mockStore;
  late LocationSyncManager syncManager;

  setUp(() {
    mockApiService = MockApiService();
    mockStore = MockPendingLocationStore();
    syncManager = LocationSyncManager(
      apiService: mockApiService,
      store: mockStore,
    );
  });

  test('queueLocation adds to store and does not flush if count < 10', () async {
    when(mockStore.insert(any)).thenAnswer((_) async => 1);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Usa conteo por usuario (countForSubject) en lugar de count global][obj: location_sync_manager_test queueLocation countForSubject]
    when(mockStore.countForSubject(any)).thenAnswer((_) async => 5);

    await syncManager.queueLocation(
      firebaseUid: 'uid',
      point: LocationPoint(latitude: 0, longitude: 0, timestamp: DateTime.now()),
    );

    verify(mockStore.insert(any)).called(1);
    verify(mockStore.countForSubject(any)).called(1);
    verifyNever(mockApiService.sendLocationBatch(any));
  });

  test('queueLocation flushes if count >= 10', () async {
    when(mockStore.insert(any)).thenAnswer((_) async => 1);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Usa conteo por usuario (countForSubject) para disparar flush][obj: location_sync_manager_test queueLocation flush]
    when(mockStore.countForSubject(any)).thenAnswer((_) async => 10);
    
    // Mock flush behavior
    final pending = List.generate(10, (i) => PendingLocation(
      id: i,
      saaSubject: 'uid',
      latitude: 0,
      longitude: 0,
      timestamp: DateTime.now().toIso8601String(),
      accuracy: 0,
      altitude: 0,
      speed: 0,
      heading: 0,
      batteryLevel: 0,
      activityType: 'still',
    ));
    
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Flush obtiene lote por usuario (getBatchForSubject)][obj: location_sync_manager_test getBatchForSubject]
    var firstBatch = true;
    when(mockStore.getBatchForSubject(any, any)).thenAnswer((_) async {
      if (firstBatch) {
        firstBatch = false;
        return pending;
      }
      return <PendingLocation>[];
    });
    when(mockStore.deleteBatch(any)).thenAnswer((_) async => 10);
    when(mockApiService.sendLocationBatch(any)).thenAnswer((_) async {});

    await syncManager.queueLocation(
      firebaseUid: 'uid',
      point: LocationPoint(latitude: 0, longitude: 0, timestamp: DateTime.now()),
    );

    verify(mockStore.insert(any)).called(1);
    verify(mockApiService.sendLocationBatch(any)).called(1);
    verify(mockStore.deleteBatch(any)).called(1);
  });
}
