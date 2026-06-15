import 'package:latlong2/latlong.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:10 UTC-5 (Lima)][desc: Estandariza marcadores para renderizar en FlutterMap o Mapbox nativo][obj: MapMarkerSpec]
class MapMarkerSpec {
  final LatLng point;
  final MapMarkerKind kind;
  final String? label;

  const MapMarkerSpec({
    required this.point,
    required this.kind,
    this.label,
  });
}

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:10 UTC-5 (Lima)][desc: Tipos de marcadores del mapa][obj: MapMarkerKind]
enum MapMarkerKind {
  userLocation,
  plannerStop,
  destination,
}
