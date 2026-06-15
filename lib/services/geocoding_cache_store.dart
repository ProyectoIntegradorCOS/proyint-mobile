import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Almacén local para caché de geocodificación][obj: GeocodingCacheStore]
class GeocodingCacheStore {
  static const String _tableName = 'geocoding_cache';
  final DatabaseService _dbService = DatabaseService();
  
  // Radio de caché en grados (aprox 20 metros)
  // 1 grado lat ~= 111km. 0.0002 ~= 22m
  static const double _cacheRadiusDegrees = 0.0002;
  // Validez del caché: 30 días
  static const int _cacheValidityMs = 30 * 24 * 60 * 60 * 1000;

  Future<Database> get database async {
    return _dbService.database;
  }

  Future<String?> getCachedAddress(double lat, double lng) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Limpieza perezosa de entradas viejas
    // (Opcional: mover a una tarea de mantenimiento si es muy costoso)
    // await db.delete(_tableName, where: 'timestamp < ?', whereArgs: [now - _cacheValidityMs]);

    // Búsqueda simple por bounding box
    final minLat = lat - _cacheRadiusDegrees;
    final maxLat = lat + _cacheRadiusDegrees;
    final minLng = lng - _cacheRadiusDegrees;
    final maxLng = lng + _cacheRadiusDegrees;

    final List<Map<String, dynamic>> results = await db.query(
      _tableName,
      where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
      whereArgs: [minLat, maxLat, minLng, maxLng],
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (results.isNotEmpty) {
      return results.first['address'] as String;
    }
    return null;
  }

  Future<void> cacheAddress(double lat, double lng, String address) async {
    final db = await database;
    await db.insert(
      _tableName,
      {
        'latitude': lat,
        'longitude': lng,
        'address': address,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
