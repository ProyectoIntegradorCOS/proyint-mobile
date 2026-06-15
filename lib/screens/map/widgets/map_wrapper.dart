import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:url_launcher/url_launcher.dart';

import '../../../config/mapbox_config.dart';
import '../../../config/feature_flags.dart';
import '../widgets/dialogs/map_layers_dialog.dart';
import 'map_marker_spec.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:10 UTC-5 (Lima)][desc: Wrapper que permite alternar entre mapa FlutterMap (OSM) y Mapbox Maps SDK nativo según feature-flag][obj: MapWrapper]
class MapWrapper extends StatefulWidget {
  final fm.MapController mapController;
  final LatLng center;
  final List<LatLng> routePoints;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:30 UTC-5 (Lima)][desc: Ruta pendiente (local DB) para pintar en otro color][obj: MapWrapper.pendingRoutePoints]
  final List<LatLng> pendingRoutePoints;
  final List<HistoryPolylineSegment> historySegments;
  final List<LatLng> plannedRoutePoints;
  final List<MapMarkerSpec> markers;
  final BaseLayer baseLayer;
  final void Function(fm.TapPosition, LatLng)? onLongPress;
  final void Function(fm.TapPosition, LatLng)? onTap;
  final void Function(fm.MapCamera, bool)? onPositionChanged;
  final VoidCallback? onMapReady;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-23 00:30 UTC-5 (Lima)][desc: Expone instancia MapboxMap al caller para mover cámara/zoom cuando el mapa nativo está activo][obj: MapWrapper.onNativeMapCreated]
  final void Function(mb.MapboxMap map)? onNativeMapCreated;

  const MapWrapper({
    super.key,
    required this.mapController,
    required this.center,
    this.routePoints = const [],
    this.pendingRoutePoints = const [],
    this.historySegments = const [],
    this.plannedRoutePoints = const [],
    this.markers = const [],
    this.baseLayer = BaseLayer.streets,
    this.onLongPress,
    this.onTap,
    this.onPositionChanged,
    this.onMapReady,
    this.onNativeMapCreated,
  });

  @override
  State<MapWrapper> createState() => _MapWrapperState();
}

class HistoryPolylineSegment {
  const HistoryPolylineSegment({required this.points, required this.color});

  final List<LatLng> points;
  final Color color;
}

class _MapWrapperState extends State<MapWrapper> {
  mb.MapboxMap? _mbMap;
  mb.PolylineAnnotationManager? _polylineManager;
  mb.CircleAnnotationManager? _circleManager;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: MapboxOptions.setAccessToken reemplaza ResourceOptions (API mapbox_maps_flutter 2.17.x)][obj: MapWrapper._accessTokenConfigured]
  bool _accessTokenConfigured = false;

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:22 UTC-5 (Lima)][desc: Selecciona estilo para tiles raster en FlutterMap según capa base][obj: MapWrapper tile style]
  String _tileStyleIdForBaseLayer(BaseLayer layer) {
    switch (layer) {
      case BaseLayer.satellite:
        return 'mapbox/satellite-v9';
      case BaseLayer.outdoors:
        return 'mapbox/outdoors-v12';
      case BaseLayer.streets:
      default:
        return MapboxConfig.styleId;
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:22 UTC-5 (Lima)][desc: Arma URL de tiles según proveedor disponible][obj: MapWrapper tile url]
  String _tileUrlForBaseLayer(BaseLayer layer) {
    if (!MapboxConfig.isConfigured) {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    final styleId = _tileStyleIdForBaseLayer(layer);
    return 'https://api.mapbox.com/styles/v1/$styleId/tiles/256/{z}/{x}/{y}?access_token=${MapboxConfig.accessToken}';
  }

  String _styleUriForBaseLayer(BaseLayer layer) {
    String styleId;
    switch (layer) {
      case BaseLayer.satellite:
        styleId = 'mapbox/satellite-v9';
        break;
      case BaseLayer.outdoors:
        styleId = 'mapbox/outdoors-v12';
        break;
      case BaseLayer.streets:
      default:
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: Respeta MAPBOX_STYLE_ID (solo aplica a streets)][obj: MapWrapper._styleUriForBaseLayer]
        styleId = MapboxConfig.styleId;
    }
    // styleId puede venir como "mapbox/streets-v12" o "user/style".
    return styleId.startsWith('mapbox://styles/')
        ? styleId
        : 'mapbox://styles/$styleId';
  }

  @override
  void initState() {
    super.initState();
    if (FeatureFlags.enableNativeMapboxMap && MapboxConfig.isConfigured) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: Configura token global Mapbox Maps Flutter 2.17 (sin ResourceOptions en MapWidget)][obj: MapWrapper.initState]
      mb.MapboxOptions.setAccessToken(MapboxConfig.accessToken);
      _accessTokenConfigured = true;
    }
  }

  Future<void> _ensureManagers() async {
    final map = _mbMap;
    if (map == null) return;
    _polylineManager ??= await map.annotations.createPolylineAnnotationManager();
    _circleManager ??= await map.annotations.createCircleAnnotationManager();
  }

  Future<void> _syncNativeAnnotations() async {
    if (!FeatureFlags.enableNativeMapboxMap) return;
    final map = _mbMap;
    if (map == null) return;
    await _ensureManagers();

    await _polylineManager?.deleteAll();
    await _circleManager?.deleteAll();

    if (widget.historySegments.isNotEmpty) {
      for (final segment in widget.historySegments) {
        if (segment.points.length < 2) continue;
        await _polylineManager?.create(
          mb.PolylineAnnotationOptions(
            geometry: mb.LineString(
              coordinates: segment.points
                  .map((p) => mb.Position(p.longitude, p.latitude))
                  .toList(),
            ),
            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 14:13 UTC-5 (Lima)][desc: Pinta historial por segmentos (colores por día) en mapa nativo][obj: MapWrapper._syncNativeAnnotations history]
            lineColor: segment.color.value,
            lineWidth: 4.0,
          ),
        );
      }
    } else {
      final points = widget.routePoints;
      if (points.length > 1) {
        await _polylineManager?.create(
          mb.PolylineAnnotationOptions(
            geometry: mb.LineString(
              coordinates: points
                  .map((p) => mb.Position(p.longitude, p.latitude))
                  .toList(),
            ),
            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: lineColor requiere int ARGB en mapbox_maps_flutter 2.17.x][obj: MapWrapper._syncNativeAnnotations]
            lineColor: 0xFF1976D2,
            lineWidth: 4.0,
          ),
        );
      }
      final pending = widget.pendingRoutePoints;
      if (pending.length > 1) {
        await _polylineManager?.create(
          mb.PolylineAnnotationOptions(
            geometry: mb.LineString(
              coordinates: pending
                  .map((p) => mb.Position(p.longitude, p.latitude))
                  .toList(),
            ),
            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:30 UTC-5 (Lima)][desc: Ruta pendiente en color ámbar (local DB)][obj: MapWrapper._syncNativeAnnotations pending]
            lineColor: 0xFFF57C00,
            lineWidth: 4.5,
          ),
        );
      }
    }

    final planned = widget.plannedRoutePoints;
    if (planned.length > 1) {
      await _polylineManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: mb.LineString(
            coordinates: planned
                .map((p) => mb.Position(p.longitude, p.latitude))
                .toList(),
          ),
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: lineColor requiere int ARGB en mapbox_maps_flutter 2.17.x][obj: MapWrapper._syncNativeAnnotations planned]
          lineColor: 0xFF673AB7,
          lineWidth: 5.0,
        ),
      );
    }

    for (final m in widget.markers) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: Usa CircleAnnotation para marcadores (evita dependencia de sprites 'marker-15' en el style)][obj: MapWrapper._syncNativeAnnotations markers]
      final color = switch (m.kind) {
        MapMarkerKind.userLocation => 0xFFD32F2F, // red
        MapMarkerKind.plannerStop => 0xFF673AB7, // deep purple
        MapMarkerKind.destination => 0xFF2E7D32, // green
      };
      final strokeColor = switch (m.kind) {
        MapMarkerKind.userLocation => 0xFFFFFFFF,
        MapMarkerKind.plannerStop => 0xFFFFFFFF,
        MapMarkerKind.destination => 0xFFFFFFFF,
      };
      final radius = switch (m.kind) {
        MapMarkerKind.userLocation => 8.0,
        MapMarkerKind.plannerStop => 7.0,
        MapMarkerKind.destination => 8.0,
      };
      await _circleManager?.create(
        mb.CircleAnnotationOptions(
          geometry: mb.Point(
            coordinates: mb.Position(m.point.longitude, m.point.latitude),
          ),
          circleColor: color,
          circleRadius: radius,
          circleStrokeColor: strokeColor,
          circleStrokeWidth: 2.0,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MapWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Actualiza anotaciones en el mapa nativo cuando cambian puntos/marcadores.
    if (FeatureFlags.enableNativeMapboxMap &&
        (oldWidget.center != widget.center ||
            oldWidget.routePoints != widget.routePoints ||
            oldWidget.pendingRoutePoints != widget.pendingRoutePoints ||
            oldWidget.historySegments != widget.historySegments ||
            oldWidget.plannedRoutePoints != widget.plannedRoutePoints ||
            oldWidget.markers != widget.markers ||
            oldWidget.baseLayer != widget.baseLayer)) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: Si cambia baseLayer en mapa nativo, carga nuevo style antes de sincronizar anotaciones][obj: MapWrapper.didUpdateWidget]
      if (oldWidget.baseLayer != widget.baseLayer && _mbMap != null) {
        _mbMap!.loadStyleURI(_styleUriForBaseLayer(widget.baseLayer));
      }
      _syncNativeAnnotations();
    }
  }

  @override
  void dispose() {
    _polylineManager = null;
    _circleManager = null;
    _mbMap = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.enableNativeMapboxMap) {
      // Producción: mapa actual con FlutterMap, forzando OSM (según decisión de producto).
      return fm.FlutterMap(
        mapController: widget.mapController,
        options: fm.MapOptions(
          initialCenter: widget.center,
          initialZoom: 15.0,
          minZoom: 5.0,
          maxZoom: 18.0,
          onLongPress: widget.onLongPress,
          onTap: widget.onTap,
          onPositionChanged: widget.onPositionChanged,
          onMapReady: widget.onMapReady,
        ),
        children: [
          fm.TileLayer(
            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-14 13:22 UTC-5 (Lima)][desc: Cambia tiles según capa base en FlutterMap (OSM/Mapbox raster)][obj: MapWrapper FlutterMap tiles]
            key: ValueKey(
              'tiles-${widget.baseLayer.name}-${MapboxConfig.isConfigured ? 'mapbox' : 'osm'}',
            ),
            urlTemplate: _tileUrlForBaseLayer(widget.baseLayer),
            userAgentPackageName: 'pe.gob.onp.thaqhiri',
          ),
          if (widget.historySegments.isNotEmpty)
            fm.PolylineLayer(
              polylines: widget.historySegments
                  .where((segment) => segment.points.length > 1)
                  .map(
                    (segment) => fm.Polyline(
                      points: segment.points,
                      strokeWidth: 4.0,
                      color: segment.color,
                    ),
                  )
                  .toList(),
            )
          else ...[
            if (widget.routePoints.isNotEmpty)
              fm.PolylineLayer(
                polylines: [
                  fm.Polyline(
                    points: widget.routePoints,
                    strokeWidth: 4.0,
                    color: Colors.blue,
                  ),
                ],
              ),
            if (widget.pendingRoutePoints.isNotEmpty)
              fm.PolylineLayer(
                polylines: [
                  fm.Polyline(
                    points: widget.pendingRoutePoints,
                    strokeWidth: 4.5,
                    color: Colors.orange,
                  ),
                ],
              ),
          ],
          if (widget.plannedRoutePoints.length > 1)
            fm.PolylineLayer(
              polylines: [
                fm.Polyline(
                  points: widget.plannedRoutePoints,
                  strokeWidth: 5.0,
                  color: Colors.deepPurple,
                ),
              ],
            ),
          fm.MarkerLayer(
            markers: widget.markers.map((m) {
              final child = switch (m.kind) {
                MapMarkerKind.userLocation => const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 32,
                  ),
                MapMarkerKind.plannerStop => Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.place, color: Colors.deepPurple, size: 40),
                      if (m.label != null)
                        Positioned(
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.deepPurple, width: 1),
                            ),
                            child: Text(
                              m.label!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                MapMarkerKind.destination => const Icon(
                    Icons.flag,
                    color: Colors.green,
                    size: 34,
                  ),
              };
              return fm.Marker(
                point: m.point,
                width: 40,
                height: 40,
                child: child,
              );
            }).toList(),
          ),
          fm.RichAttributionWidget(
            attributions: [
              if (MapboxConfig.isConfigured)
                fm.TextSourceAttribution(
                  '© Mapbox © OpenStreetMap',
                  onTap: () => launchUrl(Uri.parse('https://www.mapbox.com/about/maps/')),
                )
              else
                fm.TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
                ),
            ],
          ),
        ],
      );
    }

    if (!_accessTokenConfigured) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: Si falta MAPBOX_ACCESS_TOKEN, cae a mapa actual para no romper en dev][obj: MapWrapper.build missing token]
      return fm.FlutterMap(
        mapController: widget.mapController,
        options: fm.MapOptions(
          initialCenter: widget.center,
          initialZoom: 15.0,
          minZoom: 5.0,
          maxZoom: 18.0,
          onLongPress: widget.onLongPress,
          onTap: widget.onTap,
          onPositionChanged: widget.onPositionChanged,
          onMapReady: widget.onMapReady,
        ),
        children: [
          fm.TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'pe.gob.onp.thaqhiri',
          ),
        ],
      );
    }

    // Dev/pruebas: Mapbox Maps SDK nativo embebido.
    // Requiere MAPBOX_ACCESS_TOKEN configurado.
    return mb.MapWidget(
      key: const ValueKey('native_mapbox_map'),
      cameraOptions: mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(widget.center.longitude, widget.center.latitude)),
        zoom: 15.0,
      ),
      styleUri: _styleUriForBaseLayer(widget.baseLayer),
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:25 UTC-5 (Lima)][desc: Propaga tap/longTap del mapa nativo a handlers existentes (route planner / seleccionar en mapa)][obj: MapWrapper.MapWidget gesture bridge]
      onTapListener: (ctx) {
        if (widget.onTap == null) return;
        final tp = fm.TapPosition(
          Offset(ctx.touchPosition.x, ctx.touchPosition.y),
          Offset(ctx.touchPosition.x, ctx.touchPosition.y),
        );
        final coords = ctx.point.coordinates;
        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        widget.onTap!(
          tp,
          LatLng(lat, lon),
        );
      },
      onLongTapListener: (ctx) {
        if (widget.onLongPress == null) return;
        final tp = fm.TapPosition(
          Offset(ctx.touchPosition.x, ctx.touchPosition.y),
          Offset(ctx.touchPosition.x, ctx.touchPosition.y),
        );
        final coords = ctx.point.coordinates;
        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        widget.onLongPress!(
          tp,
          LatLng(lat, lon),
        );
      },
      // Si cambia el style (baseLayer), al cargar style volvemos a inyectar anotaciones.
      onStyleLoadedListener: (_) async {
        await _ensureManagers();
        await _syncNativeAnnotations();
      },
      onMapCreated: (map) async {
        _mbMap = map;
        widget.onNativeMapCreated?.call(map);
        await _ensureManagers();
        await _syncNativeAnnotations();
        widget.onMapReady?.call();
      },
    );
  }
}
