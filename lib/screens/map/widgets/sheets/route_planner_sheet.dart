// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 13:35 UTC-5 (Lima)][desc: Widget extraído para planificador de rutas][obj: RoutePlannerSheet]
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../models/destination.dart';
import '../../../../services/mapbox_service.dart';
import '../../../../utils/logger.dart';
import '../../controllers/route_controller.dart';

class RoutePlannerSheet extends StatefulWidget {
  final RouteController routeController;
  final MapboxService mapboxService;
  final LatLng center;
  final MapController mapController;
  final Function(String) onError;

  const RoutePlannerSheet({
    Key? key,
    required this.routeController,
    required this.mapboxService,
    required this.center,
    required this.mapController,
    required this.onError,
  }) : super(key: key);

  @override
  State<RoutePlannerSheet> createState() => _RoutePlannerSheetState();
}

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:55 UTC-5 (Lima)][desc: Sugerencias mixtas para el planificador: POIs via Search Box (requiere retrieve) y direcciones via Geocoding v6 (con coordenadas)][obj: RoutePlannerSheet suggestions model]
sealed class _PlannerSuggestion {
  const _PlannerSuggestion();
  String get title;
  String? get subtitle;
}

class _PlannerInfoSuggestion extends _PlannerSuggestion {
  const _PlannerInfoSuggestion(this._title, {String? subtitle}) : _subtitle = subtitle;
  final String _title;
  final String? _subtitle;

  @override
  String get title => _title;

  @override
  String? get subtitle => _subtitle;
}

class _PlannerPoiSuggestion extends _PlannerSuggestion {
  const _PlannerPoiSuggestion(this.mapboxId, this._title, this._subtitle);
  final String mapboxId;
  final String _title;
  final String? _subtitle;

  @override
  String get title => _title;

  @override
  String? get subtitle => _subtitle;
}

class _PlannerAddressSuggestion extends _PlannerSuggestion {
  const _PlannerAddressSuggestion(this.destination);
  final Destination destination;

  @override
  String get title => destination.name;

  @override
  String? get subtitle =>
      'Lat: ${destination.latitude.toStringAsFixed(5)}, Lng: ${destination.longitude.toStringAsFixed(5)}';
}

class _RoutePlannerSheetState extends State<RoutePlannerSheet> {
  final TextEditingController _queryController = TextEditingController();
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:55 UTC-5 (Lima)][desc: Lista de sugerencias mixtas (POI+dirección) para UI][obj: RoutePlannerSheet._suggestions]
  List<_PlannerSuggestion> _suggestions = [];
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:25 UTC-5 (Lima)][desc: Debounce de búsqueda para evitar exceso de llamadas a Mapbox al tipear][obj: RoutePlannerSheet._searchDebounce]
  Timer? _searchDebounce;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:55 UTC-5 (Lima)][desc: Search Box requiere session_token para asociar suggest/retrieve; se mantiene por sesión de tipeo][obj: RoutePlannerSheet._searchSessionToken]
  String? _searchSessionToken;
  late RoutingMode _localMode;
  late bool _localOptimize;
  late bool _localFixOrigin;
  late bool _localFixDestination;
  late bool _localUseCurrent;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 01:25 UTC-5 (Lima)][desc: Search Box API (según docs) solo soporta US/CA/Europa; en PE desactivamos POIs por Search Box para evitar resultados irrelevantes][obj: RoutePlannerSheet._isSearchBoxSupportedForCountry]
  bool _isSearchBoxSupportedForCountry(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) return true;
    final c = countryCode.toUpperCase();
    if (c == 'US' || c == 'CA') return true;
    // Nota: la lista completa de Europa es extensa; para este proyecto el caso crítico es PE.
    // Se mantiene como "false" por defecto para países fuera de US/CA.
    return false;
  }

  @override
  void initState() {
    super.initState();
    _localMode = widget.routeController.routingMode;
    _localOptimize = widget.routeController.optimizeStops;
    _localFixOrigin = widget.routeController.fixOriginFirst;
    _localFixDestination = widget.routeController.fixDestinationLast;
    _localUseCurrent = widget.routeController.useCurrentAsOrigin;
  }

  String? _nearbyBboxString(LatLng center, double deltaDegrees) {
    final minLat = center.latitude - deltaDegrees;
    final maxLat = center.latitude + deltaDegrees;
    final minLon = center.longitude - deltaDegrees;
    final maxLon = center.longitude + deltaDegrees;
    return '${minLon.toStringAsFixed(6)},${minLat.toStringAsFixed(6)},${maxLon.toStringAsFixed(6)},${maxLat.toStringAsFixed(6)}';
  }

  String? _currentViewportBboxString() {
    try {
      final bounds = widget.mapController.camera.visibleBounds;
      final south = bounds.south;
      final west = bounds.west;
      final north = bounds.north;
      final east = bounds.east;
      return '${west.toStringAsFixed(6)},${south.toStringAsFixed(6)},${east.toStringAsFixed(6)},${north.toStringAsFixed(6)}';
    } catch (_) {
      return null;
    }
  }

  double _deltaForZoom(double zoom) {
    if (zoom >= 16) return 0.02; // ~2 km
    if (zoom >= 15) return 0.03;
    if (zoom >= 14) return 0.05;
    if (zoom >= 13) return 0.08;
    if (zoom >= 12) return 0.12;
    if (zoom >= 11) return 0.20;
    if (zoom >= 10) return 0.35;
    return 0.6; // very broad
  }

  String? _dynamicLocalBboxString() {
    final byViewport = _currentViewportBboxString();
    if (byViewport != null) return byViewport;
    double z;
    try {
      z = widget.mapController.camera.zoom;
    } catch (_) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:30 UTC-5 (Lima)][desc: Cuando se usa mapa nativo (sin FlutterMap renderizado), evita leer zoom del MapController y usa un valor por defecto][obj: RoutePlannerSheet._dynamicLocalBboxString native fallback]
      z = 15.0;
    }
    final delta = _deltaForZoom(z);
    return _nearbyBboxString(widget.center, delta);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 15:20 UTC-5 (Lima)][desc: Ordena resultados de geocoding por cercanía al centro actual (mejora relevancia para queries genéricas)][obj: RoutePlannerSheet._rankByProximity]
  List<Destination> _rankByProximity(List<Destination> results, LatLng proximity) {
    if (results.isEmpty) return results;
    final d = Distance();
    final withMeters = results
        .map((r) => MapEntry(
              r,
              d.as(LengthUnit.Meter, proximity, LatLng(r.latitude, r.longitude)),
            ))
        .toList();
    withMeters.sort((a, b) => a.value.compareTo(b.value));
    return withMeters.map((e) => e.key).toList();
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 15:20 UTC-5 (Lima)][desc: Aplica filtro suave por cercanía; si no hay cerca, devuelve lista completa ordenada][obj: RoutePlannerSheet._preferNearby]
  List<Destination> _preferNearby(List<Destination> ranked, LatLng proximity) {
    if (ranked.isEmpty) return ranked;
    final d = Distance();
    final near = <Destination>[];
    for (final r in ranked) {
      final meters = d.as(LengthUnit.Meter, proximity, LatLng(r.latitude, r.longitude));
      if (meters <= 60000) {
        near.add(r);
      }
    }
    return near.isNotEmpty ? near : ranked;
  }

  Future<void> _addSuggestion(_PlannerSuggestion s) async {
    if (widget.routeController.plannerStops.length >= 5) {
      widget.onError('Máximo 5 destinos');
      return;
    }
    if (s is _PlannerInfoSuggestion) return;
    if (s is _PlannerAddressSuggestion) {
      widget.routeController.addStop(s.destination);
      setState(() => _suggestions = []);
      _queryController.clear();
      return;
    }
    if (s is _PlannerPoiSuggestion) {
      final session = _searchSessionToken ?? widget.mapboxService.newSearchSessionToken();
      _searchSessionToken = session;
      final d = await widget.mapboxService.searchBoxRetrieve(
        s.mapboxId,
        sessionToken: session,
      );
      widget.routeController.addStop(d);
      setState(() => _suggestions = []);
      _queryController.clear();
      return;
    }
  }

  Future<void> _addBySearch() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    try {
      final bbox = _dynamicLocalBboxString();
      logDebug('RoutePlanner search(add)', details: 'q="$q" center=${widget.center} bbox=${bbox ?? "-"}');

      // Si hay sugerencias visibles, toma la primera.
      if (_suggestions.isNotEmpty) {
        await _addSuggestion(_suggestions.first);
        return;
      }

      // POIs -> Search Box (solo si está soportado para el país). Para PE: deshabilitado.
      if (_isSearchBoxSupportedForCountry('PE')) {
        final session = _searchSessionToken ?? widget.mapboxService.newSearchSessionToken();
        _searchSessionToken = session;
        final poi = await widget.mapboxService.searchBoxSuggestPois(
          q,
          sessionToken: session,
          proximity: widget.center,
          country: 'PE',
          limit: 5,
          bbox: bbox,
        );
        if (poi.isNotEmpty) {
          final d = await widget.mapboxService.searchBoxRetrieve(
            poi.first.mapboxId,
            sessionToken: session,
          );
          widget.routeController.addStop(d);
          setState(() => _suggestions = []);
          _queryController.clear();
          return;
        }
      }

      // Direcciones -> Geocoding v6
      var results = await widget.mapboxService.geocode(
        q,
        proximity: widget.center,
        country: 'PE',
        limit: 15,
        bbox: bbox,
        types: 'address,street,place,locality,neighborhood',
      );
      if (results.isEmpty) {
        results = await widget.mapboxService.geocode(
          q,
          proximity: widget.center,
          country: 'PE',
          limit: 15,
          types: 'address,street,place,locality,neighborhood',
        );
      }
      if (results.isEmpty) {
        widget.onError(
          'Sin resultados para "$q". Nota: Search Box (POIs) no tiene cobertura para Perú; prueba con una dirección exacta.',
        );
        return;
      }
      if (results.length > 1 && q.length >= 6) {
        final strict = await widget.mapboxService.geocode(
          q,
          proximity: widget.center,
          country: 'PE',
          limit: 15,
          bbox: bbox,
          types: 'address,street,place,locality,neighborhood',
          fuzzyMatch: false,
        );
        if (strict.isNotEmpty) results = strict;
      }
      final ranked = _rankByProximity(results, widget.center);
      results = _preferNearby(ranked, widget.center);
      logDebug('RoutePlanner geocode(add) results', details: 'count=${results.length} first="${results.first.name}"');
      widget.routeController.addStop(results.first);
      setState(() => _suggestions = []);
      _queryController.clear();
    } catch (e) {
      widget.onError('Error buscando: $e');
    }
  }

  void _searchSuggestions(String q) async {
    final query = q.trim();
    if (query.length < 3) {
      _searchSessionToken = null;
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final bbox = _dynamicLocalBboxString();
        final session = _searchSessionToken ?? widget.mapboxService.newSearchSessionToken();
        _searchSessionToken = session;
        logDebug('RoutePlanner search(suggest)', details: 'q="$query" center=${widget.center} bbox=${bbox ?? "-"} session=${session.substring(0, 8)}');

        final country = 'PE';
        final searchBoxSupported = _isSearchBoxSupportedForCountry(country);
        final poi = searchBoxSupported
            ? await widget.mapboxService.searchBoxSuggestPois(
                query,
                sessionToken: session,
                proximity: widget.center,
                country: country,
                limit: 8,
                bbox: bbox,
              )
            : const <SearchBoxSuggestion>[];

        var addr = await widget.mapboxService.geocode(
          query,
          proximity: widget.center,
          country: 'PE',
          limit: 10,
          bbox: bbox,
          types: 'address,street,place,locality,neighborhood',
        );
        if (addr.isEmpty) {
          addr = await widget.mapboxService.geocode(
            query,
            proximity: widget.center,
            country: 'PE',
            limit: 10,
            types: 'address,street,place,locality,neighborhood',
          );
        }
        final ranked = _preferNearby(_rankByProximity(addr, widget.center), widget.center);

        final merged = <_PlannerSuggestion>[
          if (!searchBoxSupported)
            const _PlannerInfoSuggestion(
              'POIs no disponibles para Perú',
              subtitle: 'Search Box API solo soporta EE. UU., Canadá y Europa. Usa una dirección.',
            ),
          ...poi.map((p) => _PlannerPoiSuggestion(p.mapboxId, p.name, p.subtitle)),
          ...ranked.map((d) => _PlannerAddressSuggestion(d)),
        ];
        if (mounted) setState(() => _suggestions = merged);
      } catch (e) {
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 01:05 UTC-5 (Lima)][desc: Log de error de sugerencias para diagnosticar cuando no se muestra lista (Search Box/Geocoding)][obj: RoutePlannerSheet._searchSuggestions catch]
        logWarn('RoutePlanner suggest falló', details: e.toString());
        if (mounted) setState(() => _suggestions = []);
      }
    });
  }

  Future<void> _calculate() async {
    if (_localUseCurrent) {
      if (widget.routeController.plannerStops.isEmpty) {
        widget.onError('Agrega al menos un destino');
        return;
      }
    } else {
      if (widget.routeController.plannerStops.length < 2) {
        widget.onError('Agrega al menos origen y destino');
        return;
      }
    }
    try {
      final points = <LatLng>[
        if (_localUseCurrent) widget.center,
        ...widget.routeController.plannerStops
            .map((d) => LatLng(d.latitude, d.longitude))
            .toList(),
      ];
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 15:20 UTC-5 (Lima)][desc: Aclara cuándo aplica optimización y deja traza de request (para diagnosticar rutas no óptimas)][obj: RoutePlannerSheet._calculate logs]
      if (_localOptimize && points.length <= 2) {
        widget.onError('Optimizar orden requiere al menos 2 destinos; se calculará ruta directa.');
        logInfo(
          'RoutePlanner optimize: no aplica (menos de 2 destinos)',
          details: 'points=${points.length} useCurrent=$_localUseCurrent',
        );
      }
      logInfo(
        'RoutePlanner calculate',
        details: 'mode=$_localMode optimize=$_localOptimize points=${points.map((p) => "${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}").join(" | ")}',
      );
      final result = (_localOptimize && points.length > 2)
          ? await widget.mapboxService.optimize(
              mode: _localMode,
              waypoints: points,
              sourceFirst: _localUseCurrent ? true : _localFixOrigin,
              destinationLast: _localFixDestination,
            )
          : await widget.mapboxService.directions(
              mode: _localMode,
              waypoints: points,
            );
      if (!mounted) return;

      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Si viene orden de optimización, reordena paradas para reflejar la ruta óptima][obj: RoutePlannerSheet._calculate apply waypointOrder]
      if (_localOptimize && result.waypointOrder != null) {
        final order = result.waypointOrder!;
        final currentStops = List<Destination>.from(widget.routeController.plannerStops);
        final reorderedStops = <Destination>[];

        final offset = _localUseCurrent ? 1 : 0;
        for (final originalIndex in order) {
          if (originalIndex < offset) continue; // ignora origen actual si aplica
          final stopIndex = originalIndex - offset;
          if (stopIndex >= 0 && stopIndex < currentStops.length) {
            reorderedStops.add(currentStops[stopIndex]);
          }
        }
        if (reorderedStops.length == currentStops.length) {
          widget.routeController.replaceStops(reorderedStops);
        }
      }

      widget.routeController.setActiveRoute(result);
      Navigator.of(context).pop();
    } catch (e) {
      widget.onError('No se pudo calcular ruta: $e');
    }
  }

  void _removeAt(int index) {
    widget.routeController.removeStop(index);
    setState(() {});
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchSessionToken = null;
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to controller changes to update UI if needed
    return AnimatedBuilder(
      animation: widget.routeController,
      builder: (context, _) {
        final plannerStops = widget.routeController.plannerStops;
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 14:55 UTC-5 (Lima)][desc: Evita overflow del bottom-sheet usando ListView scrollable en vez de Column fija][obj: RoutePlannerSheet build layout]
        final maxHeight = MediaQuery.of(context).size.height * 0.90;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 12,
              ),
              child: ListView(
                children: [
                  Text(
                    'Planificador de ruta',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 15:05 UTC-5 (Lima)][desc: Evita overflow horizontal en pantallas angostas usando Wrap para chips de modo][obj: RoutePlannerSheet routing mode chips wrap]
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Caminar'),
                        selected: _localMode == RoutingMode.walking,
                        onSelected: (_) {
                          setState(() => _localMode = RoutingMode.walking);
                          widget.routeController.setRoutingMode(RoutingMode.walking);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Conducir (aprox. bus)'),
                        selected: _localMode == RoutingMode.driving,
                        onSelected: (_) {
                          setState(() => _localMode = RoutingMode.driving);
                          widget.routeController.setRoutingMode(RoutingMode.driving);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Conducir (tráfico)'),
                        selected: _localMode == RoutingMode.drivingTraffic,
                        onSelected: (_) {
                          setState(() => _localMode = RoutingMode.drivingTraffic);
                          widget.routeController.setRoutingMode(RoutingMode.drivingTraffic);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _queryController,
                          decoration: const InputDecoration(
                            labelText: 'Buscar dirección o lugar',
                          ),
                          onChanged: _searchSuggestions,
                          onSubmitted: (_) => _addBySearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addBySearch,
                        child: const Text('Añadir'),
                      ),
                    ],
                  ),
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: Material(
                        elevation: 2,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final s = _suggestions[index];
                            return ListTile(
                              dense: true,
                              title: Text(s.title),
                              subtitle: s.subtitle != null ? Text(s.subtitle!) : null,
                              trailing: s is _PlannerInfoSuggestion
                                  ? null
                                  : TextButton(
                                      onPressed: () => _addSuggestion(s),
                                      child: const Text('Añadir'),
                                    ),
                              onTap: () => _addSuggestion(s),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.routeController.setSelectingOnMap(true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Selecciona un punto en el mapa (tap o long-press)',
                            ),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Seleccionar en el mapa'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _localUseCurrent,
                          onChanged: (v) {
                            setState(() => _localUseCurrent = v);
                            widget.routeController.configureOriginDestination(
                              useCurrentAsOrigin: v,
                            );
                          },
                        ),
                        const Text('Usar mi ubicación como origen'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _localOptimize,
                          onChanged: (v) {
                            setState(() => _localOptimize = v);
                            widget.routeController.setOptimizeStops(v);
                          },
                        ),
                        const Text('Optimizar orden'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: _localFixOrigin,
                              onChanged: (v) {
                                setState(() => _localFixOrigin = v);
                                widget.routeController.configureOriginDestination(
                                  fixOrigin: v,
                                );
                              },
                            ),
                            const Text('Fijar origen (1°)'),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: _localFixDestination,
                              onChanged: (v) {
                                setState(() => _localFixDestination = v);
                                widget.routeController.configureOriginDestination(
                                  fixDestination: v,
                                );
                              },
                            ),
                            const Text('Fijar destino (último)'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...plannerStops.asMap().entries.map((entry) {
                    final index = entry.key;
                    final d = entry.value;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(d.name),
                      subtitle: Text(
                        'Lat: ${d.latitude.toStringAsFixed(5)}, Lng: ${d.longitude.toStringAsFixed(5)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeAt(index),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          widget.routeController.clearStops();
                          widget.routeController.setActiveRoute(null);
                          setState(() {});
                        },
                        child: const Text('Limpiar selección'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _calculate,
                        icon: const Icon(Icons.alt_route),
                        label: const Text('Calcular ruta'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
