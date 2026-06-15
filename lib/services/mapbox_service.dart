import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/mapbox_config.dart';
import '../models/destination.dart';
import '../models/route_models.dart';
import '../utils/logger.dart';
import 'geocoding_cache_store.dart';
import 'package:uuid/uuid.dart';

class MapboxServiceException implements Exception {
  final String message;
  MapboxServiceException(this.message);
  @override
  String toString() => 'MapboxServiceException: $message';
}

enum RoutingMode { walking, driving, drivingTraffic }

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:40 UTC-5 (Lima)][desc: Modelo de sugerencia POI vía Search Box (requiere retrieve para coordenadas)][obj: SearchBoxSuggestion]
class SearchBoxSuggestion {
  SearchBoxSuggestion({
    required this.mapboxId,
    required this.name,
    this.subtitle,
  });

  final String mapboxId;
  final String name;
  final String? subtitle;
}

class MapboxService {
  MapboxService({http.Client? client, String? accessToken})
      : _client = client ?? http.Client(),
        _overrideToken = accessToken,
        _uuid = const Uuid();

  final http.Client _client;
  final String? _overrideToken;
  final Uuid _uuid;

  String get _token {
    final t = _overrideToken ?? MapboxConfig.accessToken;
    if (t.isEmpty) {
      throw MapboxServiceException('Mapbox token no configurado');
    }
    return t;
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:40 UTC-5 (Lima)][desc: Geocoding v6 (forward) para direcciones/lugares administrativos; POIs se manejan por Search Box][obj: MapboxService.geocode]
  Future<List<Destination>> geocode(
    String query, {
    LatLng? proximity,
    String? country,
    String language = 'es',
    int limit = 5,
    String? bbox, // format: minLon,minLat,maxLon,maxLat
    String? types, // e.g., 'address,street,place,locality,neighborhood'
    bool fuzzyMatch = true,
  }) async {
    final params = <String, String>{
      'autocomplete': 'true',
      'limit': limit.toString(),
      'language': language,
      'access_token': _token,
      // Geocoding v6 mantiene fuzzy con `fuzzy_match`.
      'fuzzy_match': fuzzyMatch ? 'true' : 'false',
      if (proximity != null)
        'proximity': '${proximity.longitude.toStringAsFixed(6)},${proximity.latitude.toStringAsFixed(6)}',
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 01:05 UTC-5 (Lima)][desc: country se envía en mayúsculas (ISO-3166-1 alpha-2) para compatibilidad con APIs Search/Geocoding][obj: MapboxService.geocode country]
      if (country != null && country.isNotEmpty) 'country': country.toUpperCase(),
      if (bbox != null && bbox.isNotEmpty) 'bbox': bbox,
      if (types != null && types.isNotEmpty) 'types': types,
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final uri = Uri.parse('https://api.mapbox.com/search/geocode/v6/forward?q=${Uri.encodeComponent(query)}&$qs');
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 01:05 UTC-5 (Lima)][desc: Log resumido de request Geocoding v6 (sin token) para diagnóstico][obj: MapboxService.geocode log]
    logDebug(
      'Mapbox geocode(v6) -> forward',
      // Nota: Mapbox espera proximity como "lon,lat".
      details: 'q="${query.length > 80 ? query.substring(0, 80) : query}" country=${country ?? "-"} lang=$language limit=$limit bbox=${bbox ?? "-"} types=${types ?? "-"} prox=${proximity != null ? "${proximity.longitude.toStringAsFixed(4)},${proximity.latitude.toStringAsFixed(4)}" : "-"}',
    );
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      logWarn(
        'Mapbox geocode(v6) error',
        details: 'status=${resp.statusCode} bodyPreview=${resp.body.length > 180 ? resp.body.substring(0, 180) : resp.body}',
      );
      throw MapboxServiceException(
          'Fallo geocoding (${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final features = (data['features'] as List<dynamic>? ?? []);
    logDebug('Mapbox geocode(v6) OK', details: 'count=${features.length}');
    return features.map((f) {
      final m = f as Map<String, dynamic>;
      final geometry = (m['geometry'] as Map<String, dynamic>?);
      final coords = (geometry?['coordinates'] as List<dynamic>?);
      if (coords == null || coords.length < 2) {
        return Destination(
          id: (m['id'] as String?) ?? 'unknown',
          name: (m['properties'] as Map<String, dynamic>?)?['name'] as String? ??
              'Sin nombre',
          latitude: 0,
          longitude: 0,
          source: DestinationSource.search,
        );
      }
      final props = (m['properties'] as Map<String, dynamic>?);
      final name = (props?['name'] as String?) ??
          (props?['full_address'] as String?) ??
          (props?['place_formatted'] as String?) ??
          'Sin nombre';
      return Destination(
        id: props?['mapbox_id'] as String? ?? (m['id'] as String? ?? 'unknown'),
        name: name,
        latitude: (coords[1] as num).toDouble(),
        longitude: (coords[0] as num).toDouble(),
        source: DestinationSource.search,
      );
    }).toList();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:40 UTC-5 (Lima)][desc: Search Box Suggest para POIs (lugares/marcas/categorías). Requiere retrieve para coordenadas.][obj: MapboxService.searchBoxSuggestPois]
  Future<List<SearchBoxSuggestion>> searchBoxSuggestPois(
    String query, {
    required String sessionToken,
    LatLng? proximity,
    String? country,
    String language = 'es',
    int limit = 8,
    String? bbox, // format: minLon,minLat,maxLon,maxLat
  }) async {
    final params = <String, String>{
      'q': query,
      'access_token': _token,
      'session_token': sessionToken,
      'language': language,
      'limit': limit.toString(),
      'types': 'poi',
      if (proximity != null)
        'proximity': '${proximity.longitude.toStringAsFixed(6)},${proximity.latitude.toStringAsFixed(6)}',
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 01:05 UTC-5 (Lima)][desc: country en mayúsculas para Search Box][obj: MapboxService.searchBoxSuggestPois country]
      if (country != null && country.isNotEmpty) 'country': country.toUpperCase(),
      if (bbox != null && bbox.isNotEmpty) 'bbox': bbox,
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final uri = Uri.parse('https://api.mapbox.com/search/searchbox/v1/suggest?$qs');
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 01:05 UTC-5 (Lima)][desc: Log resumido de request Search Box suggest (sin token) para diagnóstico][obj: MapboxService.searchBoxSuggestPois log]
    logDebug(
      'Mapbox searchbox -> suggest',
      // Nota: Mapbox espera proximity como "lon,lat".
      details: 'q="${query.length > 80 ? query.substring(0, 80) : query}" session=${sessionToken.substring(0, 8)} country=${country ?? "-"} lang=$language limit=$limit bbox=${bbox ?? "-"} prox=${proximity != null ? "${proximity.longitude.toStringAsFixed(4)},${proximity.latitude.toStringAsFixed(4)}" : "-"}',
    );
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      logWarn(
        'Mapbox searchbox suggest error',
        details: 'status=${resp.statusCode} bodyPreview=${resp.body.length > 180 ? resp.body.substring(0, 180) : resp.body}',
      );
      throw MapboxServiceException('Fallo searchbox suggest (${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final suggestions = (data['suggestions'] as List<dynamic>? ?? const []);
    logDebug('Mapbox searchbox suggest OK', details: 'count=${suggestions.length}');
    return suggestions.map((s) {
      final m = s as Map<String, dynamic>;
      final name = (m['name'] as String?) ?? (m['text'] as String?) ?? 'Sin nombre';
      final mapboxId = (m['mapbox_id'] as String?) ?? (m['id'] as String?) ?? 'unknown';
      final subtitle = (m['place_formatted'] as String?) ??
          (m['full_address'] as String?) ??
          (m['address'] as String?);
      return SearchBoxSuggestion(mapboxId: mapboxId, name: name, subtitle: subtitle);
    }).toList();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:40 UTC-5 (Lima)][desc: Search Box Retrieve: obtiene coordenadas para un POI sugerido usando mapbox_id y session_token][obj: MapboxService.searchBoxRetrieve]
  Future<Destination> searchBoxRetrieve(
    String mapboxId, {
    required String sessionToken,
  }) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 01:05 UTC-5 (Lima)][desc: Log resumido de request Search Box retrieve (sin token) para diagnóstico][obj: MapboxService.searchBoxRetrieve log]
    logDebug(
      'Mapbox searchbox -> retrieve',
      details: 'mapboxId=${mapboxId.length > 24 ? mapboxId.substring(0, 24) : mapboxId} session=${sessionToken.substring(0, 8)}',
    );
    final uri = Uri.parse(
      'https://api.mapbox.com/search/searchbox/v1/retrieve/${Uri.encodeComponent(mapboxId)}'
      '?access_token=${Uri.encodeComponent(_token)}&session_token=${Uri.encodeComponent(sessionToken)}',
    );
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      logWarn(
        'Mapbox searchbox retrieve error',
        details: 'status=${resp.statusCode} bodyPreview=${resp.body.length > 180 ? resp.body.substring(0, 180) : resp.body}',
      );
      throw MapboxServiceException('Fallo searchbox retrieve (${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final features = (data['features'] as List<dynamic>? ?? const []);
    logDebug('Mapbox searchbox retrieve OK', details: 'features=${features.length}');
    if (features.isEmpty) {
      throw MapboxServiceException('SearchBox retrieve: sin features');
    }
    final f = features.first as Map<String, dynamic>;
    final props = (f['properties'] as Map<String, dynamic>?);
    final geometry = (f['geometry'] as Map<String, dynamic>?);
    final coords = (geometry?['coordinates'] as List<dynamic>?);
    if (coords == null || coords.length < 2) {
      throw MapboxServiceException('SearchBox retrieve: sin coordenadas');
    }
    final name = (props?['name'] as String?) ??
        (props?['full_address'] as String?) ??
        (props?['place_formatted'] as String?) ??
        'Sin nombre';
    return Destination(
      id: props?['mapbox_id'] as String? ?? mapboxId,
      name: name,
      latitude: (coords[1] as num).toDouble(),
      longitude: (coords[0] as num).toDouble(),
      source: DestinationSource.search,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:40 UTC-5 (Lima)][desc: Genera session_token para agrupar suggest/retrieve en Search Box][obj: MapboxService.newSearchSessionToken]
  String newSearchSessionToken() => _uuid.v4();

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Implementa caché local para geocodificación inversa][obj: MapboxService.reverseGeocode]
  Future<String> reverseGeocode(LatLng point) async {
    final cacheStore = GeocodingCacheStore();
    final cached = await cacheStore.getCachedAddress(point.latitude, point.longitude);
    if (cached != null) {
      logDebug('Dirección obtenida de caché local');
      return cached;
    }

    String result;
    try {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:40 UTC-5 (Lima)][desc: Migra reverse geocode a Geocoding v6 (fallback a v5 si falla) ][obj: MapboxService.reverseGeocode v6]
      final uri = Uri.parse(
        'https://api.mapbox.com/search/geocode/v6/reverse'
        '?longitude=${point.longitude.toStringAsFixed(6)}'
        '&latitude=${point.latitude.toStringAsFixed(6)}'
        '&limit=1&language=es&access_token=${Uri.encodeComponent(_token)}',
      );
      final resp = await _client.get(uri);
      if (resp.statusCode != 200) {
        throw MapboxServiceException('Fallo reverse geocoding v6 (${resp.statusCode})');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = (data['features'] as List<dynamic>? ?? const []);
      if (features.isEmpty) {
        result = '${point.latitude},${point.longitude}';
      } else {
        final f = features.first as Map<String, dynamic>;
        final props = (f['properties'] as Map<String, dynamic>?);
        result = (props?['full_address'] as String?) ??
            (props?['place_formatted'] as String?) ??
            (props?['name'] as String?) ??
            '${point.latitude},${point.longitude}';
      }
    } catch (e) {
      logWarn('Reverse geocode v6 falló, fallback a v5', details: e.toString());
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '${point.longitude},${point.latitude}.json?limit=1&language=es&access_token=${Uri.encodeComponent(_token)}',
      );
      final resp = await _client.get(uri);
      if (resp.statusCode != 200) {
        throw MapboxServiceException('Fallo reverse geocoding (${resp.statusCode})');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = (data['features'] as List<dynamic>? ?? const []);
      if (features.isEmpty) {
        result = '${point.latitude},${point.longitude}';
      } else {
        result = (features.first as Map<String, dynamic>)['place_name'] as String? ??
            '${point.latitude},${point.longitude}';
      }
    }

    await cacheStore.cacheAddress(point.latitude, point.longitude, result);
    return result;
  }

  String _profile(RoutingMode mode) {
    switch (mode) {
      case RoutingMode.walking:
        return 'walking';
      case RoutingMode.drivingTraffic:
        return 'driving-traffic';
      case RoutingMode.driving:
        return 'driving';
    }
  }

  Future<RouteResult> directions({
    required RoutingMode mode,
    required List<LatLng> waypoints,
  }) async {
    if (waypoints.length < 2) {
      throw MapboxServiceException('Se requieren al menos 2 puntos');
    }
    final coords = waypoints
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/${_profile(mode)}/$coords'
      '?alternatives=false&geometries=geojson&steps=true&overview=full&access_token=${_token}',
    );
    var resp = await _client.get(uri);
    if (resp.statusCode != 200 && mode == RoutingMode.drivingTraffic) {
      // Fallback a driving si el plan no soporta tráfico
      final fallback = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
        '?alternatives=false&geometries=geojson&steps=true&overview=full&access_token=${_token}',
      );
      resp = await _client.get(fallback);
    }
    if (resp.statusCode != 200) {
      throw MapboxServiceException('Fallo directions (${resp.statusCode}): ${resp.body}');
    }
    return _parseDirections(resp.body);
  }

  Future<List<RouteResult>> directionsAlternatives({
    required RoutingMode mode,
    required LatLng origin,
    required LatLng destination,
    int maxAlternatives = 4,
  }) async {
    final coords = [origin, destination]
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/${_profile(mode)}/$coords'
      '?alternatives=true&geometries=geojson&steps=true&overview=full&access_token=${_token}',
    );
    var resp = await _client.get(uri);
    if (resp.statusCode != 200 && mode == RoutingMode.drivingTraffic) {
      final fallback = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
        '?alternatives=true&geometries=geojson&steps=true&overview=full&access_token=${_token}',
      );
      resp = await _client.get(fallback);
    }
    if (resp.statusCode != 200) {
      throw MapboxServiceException('Fallo directions alternativas (${resp.statusCode}): ${resp.body}');
    }
    final list = _parseDirectionsList(resp.body);
    if (list.isEmpty) {
      throw MapboxServiceException('Sin rutas alternativas');
    }
    return list.take(maxAlternatives).toList();
  }

  Future<RouteResult> optimize({
    required RoutingMode mode,
    required List<LatLng> waypoints,
    bool sourceFirst = true,
    bool destinationLast = true,
  }) async {
    if (waypoints.length < 2) {
      throw MapboxServiceException('Se requieren al menos 2 puntos');
    }
    final coords = waypoints
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');
    final params = <String, String>{
      'geometries': 'geojson',
      'steps': 'true',
      'access_token': _token,
      'roundtrip': 'false',
      if (sourceFirst) 'source': 'first',
      if (destinationLast) 'destination': 'last',
    };
    final qs = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final uri = Uri.parse('https://api.mapbox.com/optimized-trips/v1/mapbox/${_profile(mode)}/$coords?$qs');
    var resp = await _client.get(uri);
    if (resp.statusCode != 200 && mode == RoutingMode.drivingTraffic) {
      final fallback = Uri.parse('https://api.mapbox.com/optimized-trips/v1/mapbox/driving/$coords?$qs');
      resp = await _client.get(fallback);
    }
    if (resp.statusCode != 200) {
      throw MapboxServiceException('Fallo optimization (${resp.statusCode}): ${resp.body}');
    }
    return _parseOptimization(resp.body);
  }

  RouteResult _parseDirections(String body) {
    final list = _parseDirectionsList(body);
    if (list.isEmpty) {
      throw MapboxServiceException('Sin rutas');
    }
    return list.first;
  }

  List<RouteResult> _parseDirectionsList(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return const <RouteResult>[];
    }
    return routes.map((route) {
      final r = route as Map<String, dynamic>;
      final geometry = r['geometry'] as Map<String, dynamic>;
      final coords = (geometry['coordinates'] as List<dynamic>)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      final legs = (r['legs'] as List<dynamic>? ?? []);
      final steps = <RouteStepInfo>[];
      final legInfos = <RouteLegInfo>[];
      for (final leg in legs) {
        final l = leg as Map<String, dynamic>;
        legInfos.add(RouteLegInfo(
          distanceMeters: (l['distance'] as num?)?.toDouble() ?? 0,
          durationSeconds: (l['duration'] as num?)?.toDouble() ?? 0,
        ));
        final s = (l['steps'] as List<dynamic>? ?? []);
        for (final st in s) {
          final m = st as Map<String, dynamic>;
          final maneuver = (m['maneuver'] as Map<String, dynamic>? ?? {});
          final instruction = (maneuver['instruction'] as String?) ?? '';
          steps.add(RouteStepInfo(
            instruction: instruction,
            distanceMeters: (m['distance'] as num?)?.toDouble() ?? 0,
            durationSeconds: (m['duration'] as num?)?.toDouble() ?? 0,
          ));
        }
      }
      return RouteResult(
        coordinates: coords,
        distanceMeters: (r['distance'] as num?)?.toDouble() ?? 0,
        durationSeconds: (r['duration'] as num?)?.toDouble() ?? 0,
        steps: steps,
        legs: legInfos,
        waypointOrder: null,
      );
    }).toList();
  }

  RouteResult _parseOptimization(String body) {
    // optimized-trips returns trips array similar to routes in directions
    final data = jsonDecode(body) as Map<String, dynamic>;
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Extrae el orden de waypoints optimizado para reordenar paradas en UI][obj: MapboxService._parseOptimization waypointOrder]
    final wp = (data['waypoints'] as List<dynamic>? ?? const <dynamic>[]);
    List<int>? waypointOrder;
    if (wp.isNotEmpty) {
      final indexed = <MapEntry<int, int>>[];
      for (var i = 0; i < wp.length; i++) {
        final m = wp[i] as Map<String, dynamic>;
        final wi = (m['waypoint_index'] as num?)?.toInt();
        if (wi != null) {
          indexed.add(MapEntry(i, wi));
        }
      }
      if (indexed.length == wp.length) {
        indexed.sort((a, b) => a.value.compareTo(b.value));
        waypointOrder = indexed.map((e) => e.key).toList();
      }
    }
    final trips = data['trips'] as List<dynamic>?;
    if (trips == null || trips.isEmpty) {
      throw MapboxServiceException('Sin viajes optimizados');
    }
    final r = trips.first as Map<String, dynamic>;
    final geometry = r['geometry'] as Map<String, dynamic>;
    final coords = (geometry['coordinates'] as List<dynamic>)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    final legs = (r['legs'] as List<dynamic>? ?? []);
    final steps = <RouteStepInfo>[];
    final legInfos = <RouteLegInfo>[];
    for (final leg in legs) {
      final l = leg as Map<String, dynamic>;
      legInfos.add(RouteLegInfo(
        distanceMeters: (l['distance'] as num?)?.toDouble() ?? 0,
        durationSeconds: (l['duration'] as num?)?.toDouble() ?? 0,
      ));
      final s = (l['steps'] as List<dynamic>? ?? []);
      for (final st in s) {
        final m = st as Map<String, dynamic>;
        final maneuver = (m['maneuver'] as Map<String, dynamic>? ?? {});
        final instruction = (maneuver['instruction'] as String?) ?? '';
        steps.add(RouteStepInfo(
          instruction: instruction,
          distanceMeters: (m['distance'] as num?)?.toDouble() ?? 0,
          durationSeconds: (m['duration'] as num?)?.toDouble() ?? 0,
        ));
      }
    }
    return RouteResult(
      coordinates: coords,
      distanceMeters: (r['distance'] as num?)?.toDouble() ?? 0,
      durationSeconds: (r['duration'] as num?)?.toDouble() ?? 0,
      steps: steps,
      legs: legInfos,
      waypointOrder: waypointOrder,
    );
  }
}
