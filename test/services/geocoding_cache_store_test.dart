import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_application_1/services/geocoding_cache_store.dart';

void main() {
  late GeocodingCacheStore store;

  setUpAll(() {
    // Initialize FFI for desktop/test environment
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final dbPath = p.join(await getDatabasesPath(), 'tracking_store.db');
    await databaseFactory.deleteDatabase(dbPath);
    store = GeocodingCacheStore();
  });

  test('getCachedAddress returns null if not found', () async {
    // This test might fail if DB is not mocked properly in this environment,
    // but this is the correct structure for the test.
    final result = await store.getCachedAddress(-12.0, -77.0);
    expect(result, isNull);
  });

  test('cacheAddress inserts and retrieves value', () async {
    await store.cacheAddress(-12.0, -77.0, 'Test Address');
    
    final result = await store.getCachedAddress(-12.0, -77.0);
    expect(result, equals('Test Address'));
  });
  
  test('getCachedAddress respects radius', () async {
    await store.cacheAddress(-12.0, -77.0, 'Center');
    
    // Very close point (within 0.0002 degrees)
    final close = await store.getCachedAddress(-12.0001, -77.0001);
    expect(close, equals('Center'));
    
    // Far point
    final far = await store.getCachedAddress(-12.1, -77.1);
    expect(far, isNull);
  });
}
