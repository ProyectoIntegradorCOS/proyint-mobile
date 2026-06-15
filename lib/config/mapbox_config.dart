// Centralized Mapbox configuration.
// Uses .env first, falls back to --dart-define.
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MapboxConfig {
  // Primary token for Mapbox services (tiles, directions, geocoding, optimization).
  // Usage: MAPBOX_ACCESS_TOKEN in .env or --dart-define=MAPBOX_ACCESS_TOKEN=pk.XXXX
  static String get accessToken =>
      dotenv.env['MAPBOX_ACCESS_TOKEN'] ??
      const String.fromEnvironment('MAPBOX_ACCESS_TOKEN', defaultValue: '');

  // Optional: style ID for tiles (e.g., 'mapbox/streets-v12').
  static String get styleId =>
      dotenv.env['MAPBOX_STYLE_ID'] ??
      const String.fromEnvironment('MAPBOX_STYLE_ID', defaultValue: 'mapbox/streets-v12');

  static bool get isConfigured => accessToken.isNotEmpty;
}
