// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-05 08:20 UTC-5 (Lima)][desc: Modelo para ubicación pendiente de sincronización][obj: PendingLocation]
class PendingLocation {
  final int? id;
  final String saaSubject;
  final double latitude;
  final double longitude;
  final String timestamp;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Epoch ms para retención/purga eficiente y ordenamiento consistente][obj: PendingLocation timestampEpochMs]
  final int? timestampEpochMs;
  final double accuracy;
  final double altitude;
  final double speed;
  final double heading;
  final double batteryLevel;
  final String activityType;

  PendingLocation({
    this.id,
    required this.saaSubject,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.timestampEpochMs,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.batteryLevel,
    required this.activityType,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'saaSubject': saaSubject,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
      'timestamp_epoch_ms': timestampEpochMs,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'batteryLevel': batteryLevel,
      'activityType': activityType,
    };
  }

  factory PendingLocation.fromMap(Map<String, dynamic> map) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Hace parsing tolerante de tipos numéricos desde SQLite (int/double)][obj: PendingLocation.fromMap]
    double readDouble(String key) {
      final v = map[key];
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return PendingLocation(
      id: map['id'] as int?,
      saaSubject: map['saaSubject'] as String,
      latitude: readDouble('latitude'),
      longitude: readDouble('longitude'),
      timestamp: map['timestamp'] as String,
      timestampEpochMs: (map['timestamp_epoch_ms'] as num?)?.toInt(),
      accuracy: readDouble('accuracy'),
      altitude: readDouble('altitude'),
      speed: readDouble('speed'),
      heading: readDouble('heading'),
      batteryLevel: readDouble('batteryLevel'),
      activityType: map['activityType'] as String,
    );
  }
}
