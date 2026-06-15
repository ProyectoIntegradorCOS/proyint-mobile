import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_application_1/services/pending_location_store.dart';
import 'package:flutter_application_1/models/pending_location.dart';

void main() {
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Ajusta tests a nuevo campo timestampEpochMs y conteo por usuario][obj: pending_location_store_test]
  late PendingLocationStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    store = PendingLocationStore();
  });

  test('insert adds location', () async {
    final loc = PendingLocation(
      saaSubject: 'uid',
      latitude: 10,
      longitude: 10,
      timestamp: DateTime.now().toIso8601String(),
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Incluye timestampEpochMs requerido para retención/purga en cola local][obj: pending_location_store_test timestampEpochMs]
      timestampEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      accuracy: 1,
      altitude: 1,
      speed: 0,
      heading: 0,
      batteryLevel: 100,
      activityType: 'still',
    );
    
    final id = await store.insert(loc);
    expect(id, isPositive);
    
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Verifica conteo por usuario (countForSubject) en lugar de count global][obj: pending_location_store_test countForSubject]
    final count = await store.countForSubject('uid');
    expect(count, greaterThanOrEqualTo(1));
  });

  test('getBatch returns limited items', () async {
    // Assuming DB is persistent or shared, this might be flaky if not cleared.
    // In a real test env we'd ensure clean DB.
    final batch = await store.getBatch(5);
    expect(batch.length, lessThanOrEqualTo(5));
  });
}
