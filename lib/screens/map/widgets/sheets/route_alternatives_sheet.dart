// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 13:50 UTC-5 (Lima)][desc: Widget extraído para alternativas de ruta][obj: RouteAlternativesSheet]
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:15 UTC-5 (Lima)][desc: Corrige imports de config, modelos y servicios][obj: RouteAlternativesSheet imports]
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../config/mapbox_config.dart';
import '../../../../models/route_models.dart';
import '../../../../services/mapbox_service.dart';
import '../../controllers/route_controller.dart';

class RouteAlternativesSheet extends StatefulWidget {
  final LatLng origin;
  final LatLng destination;
  final MapboxService mapboxService;
  final RouteController routeController;
  final Function(LatLng) onOpenExternal;
  final Function(RouteResult) onRouteSelected;
  final VoidCallback onCustomRoute;
  final RoutingMode routingMode;

  const RouteAlternativesSheet({
    super.key,
    required this.origin,
    required this.destination,
    required this.mapboxService,
    required this.routeController,
    required this.onOpenExternal,
    required this.onRouteSelected,
    required this.onCustomRoute,
    required this.routingMode,
  });

  @override
  State<RouteAlternativesSheet> createState() => _RouteAlternativesSheetState();
}

class _RouteAlternativesSheetState extends State<RouteAlternativesSheet> {
  List<RouteResult>? _routes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAlternatives();
  }

  Future<void> _fetchAlternatives() async {
    try {
      final routes = await widget.mapboxService.directionsAlternatives(
        mode: widget.routingMode,
        origin: widget.origin,
        destination: widget.destination,
        maxAlternatives: 4,
      );
      if (mounted) {
        setState(() {
          _routes = routes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rutas sugeridas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error: $_error'),
                ),
              )
            else if (_routes == null || _routes!.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No se encontraron rutas alternativas'),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _routes!.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final r = _routes![index];
                    final coords = r.coordinates;
                    final mid = coords.isNotEmpty
                        ? coords[coords.length ~/ 2]
                        : widget.origin;
                    return InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onRouteSelected(r);
                      },
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 120,
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter: mid,
                                    initialZoom: 12,
                                    interactionOptions:
                                        const InteractionOptions(
                                          flags: InteractiveFlag.none,
                                        ),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: MapboxConfig.isConfigured
                                          ? 'https://api.mapbox.com/styles/v1/{styleId}/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}'
                                          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      additionalOptions:
                                          MapboxConfig.isConfigured
                                          ? {
                                              'accessToken':
                                                  MapboxConfig.accessToken,
                                              'styleId':
                                                  MapboxConfig.styleId,
                                            }
                                          : const <String, String>{},
                                      userAgentPackageName:
                                          'com.example.flutter_application_1',
                                    ),
                                    if (coords.isNotEmpty)
                                      PolylineLayer(
                                        polylines: [
                                          Polyline(
                                            points: coords,
                                            color: Colors.deepPurple,
                                            strokeWidth: 4,
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Opción ${index + 1}'),
                                  Text(
                                    '${(r.distanceMeters / 1000).toStringAsFixed(2)} km • ${(r.durationSeconds / 60).toStringAsFixed(0)} min',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onOpenExternal(widget.destination);
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('Abrir en Google Maps'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onCustomRoute();
                  },
                  child: const Text('Usar mi propia ruta'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
