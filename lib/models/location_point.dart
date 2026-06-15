import '../utils/lima_time.dart';

class LocationPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;

  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Serializa timestamp con offset Lima (-05:00)][obj: LocationPoint.toJson Lima]
      'timestamp': toLimaIsoString(timestamp),
      if (accuracy != null) 'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
    };
  }

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Soporta payload de backend que usa recordedAt en vez de timestamp (historial por fecha)][obj: LocationPoint.fromJson recordedAt]
    final tsRaw = (json['timestamp'] ?? json['recordedAt']) as String?;
    if (tsRaw == null || tsRaw.isEmpty) {
      throw FormatException('LocationPoint sin timestamp/recordedAt');
    }
    return LocationPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(tsRaw),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
    );
  }
}

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:45 UTC-5 (Lima)][desc: Agrega clase LocationHistory para historial de ubicaciones][obj: LocationHistory]
class LocationHistory {
  final List<LocationPoint> points;
  final double totalDistanceKm;
  final DateTime start;
  final DateTime end;

  const LocationHistory({
    required this.points,
    required this.totalDistanceKm,
    required this.start,
    required this.end,
  });
}
