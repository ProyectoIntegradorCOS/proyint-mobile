// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 17:15 UTC-5 (Lima)][desc: Feature flags por --dart-define (activar navegación nativa solo en pruebas)][obj: FeatureFlags]
class FeatureFlags {
  // Enable native Mapbox Navigation SDK (Android) flow.
  // Default: false (producción mantiene mapa actual y comportamiento existente).
  static const bool enableNativeNavigation = bool.fromEnvironment(
    'USE_NATIVE_NAVIGATION',
    defaultValue: false,
  );

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:10 UTC-5 (Lima)][desc: Activa mapa nativo Mapbox Maps SDK embebido en Flutter (solo dev/pruebas). Producción usa mapa actual (FlutterMap/OSM).][obj: FeatureFlags.enableNativeMapboxMap]
  static const bool enableNativeMapboxMap = bool.fromEnvironment(
    'USE_MAPBOX_NATIVE_MAP',
    defaultValue: false,
  );
}
