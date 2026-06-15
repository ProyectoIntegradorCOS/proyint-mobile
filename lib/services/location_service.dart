import 'dart:async';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import '../models/location_point.dart';
import 'foreground_service_manager.dart';
import '../utils/logger.dart';

class LocationServiceException implements Exception {
  final String message;

  LocationServiceException(this.message);

  @override
  String toString() => 'LocationServiceException: $message';
}

class LocationService {
  LocationService();

  final StreamController<LocationPoint> _locationController =
      StreamController<LocationPoint>.broadcast();
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-09 15:04 UTC-5 (Lima)][desc: Ajusta settings Android para forzar alta precisión y ritmo estable][obj: LocationService._defaultSettings]
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:51 UTC-5 (Lima)][desc: Agrega AppleSettings para iOS con allowBackgroundLocationUpdates y pauseLocationUpdatesAutomatically=false][obj: LocationService._defaultSettings iOS]
  LocationSettings get _defaultSettings {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 10),
      );
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Ajusta AppleSettings sin const para compatibilidad con la versión actual de geolocator y background location en iOS][obj: LocationService._defaultSettings AppleSettings non-const]
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 10,
    );
  }

  StreamSubscription<Position>? _positionSub;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:51 UTC-5 (Lima)][desc: Suscripción al EventChannel nativo iOS para recibir puntos cuando Flutter es el receptor de LocationTracker.swift][obj: LocationService._nativeSub]
  StreamSubscription? _nativeSub;
  bool _isTracking = false;

  Stream<LocationPoint> get stream => _locationController.stream;
  bool get isTracking => _isTracking;

  Future<bool> _ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
      return false;
    }
    return true;
  }

  Future<void> start({LocationSettings? settings}) async {
    if (_isTracking) {
      logDebug('Tracking solicitado pero ya estaba activo');
      return;
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-06 18:36 UTC-5 (Lima)][desc: Evita iniciar tracking en fines de semana (solo L-V)][obj: LocationService.start weekday guard]
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      throw LocationServiceException(
        'Tracking fuera de horario permitido (solo L-V)',
      );
    }
    logDebug('Iniciando tracking de ubicación');
    final ok = await _ensurePermissions();
    if (!ok) {
      logDebug('Permisos denegados, no se puede iniciar tracking');
      throw LocationServiceException(
        'Permisos de ubicación denegados o servicio desactivado',
      );
    }

    _isTracking = true;
    await _startStream(settings ?? _defaultSettings);
  }

  Future<void> _startStream(LocationSettings settings) async {
    await _positionSub?.cancel();
    // Activar servicio foreground para mantener tracking en background (Android)
    await GetIt.I<ForegroundServiceManager>().startService();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (pos) {
        logDebug(
          'Coordenadas recibidas',
          details: 'lat=${pos.latitude}, lng=${pos.longitude}',
        );
        final point = LocationPoint(
          latitude: pos.latitude,
          longitude: pos.longitude,
          timestamp: pos.timestamp.toUtc(),
          accuracy: pos.accuracy,
          altitude: pos.altitude,
          speed: pos.speed,
          heading: pos.heading,
        );
        if (!_locationController.isClosed) {
          _locationController.add(point);
        }
      },
      onError: (error, stackTrace) {
        logError(
          'Error en stream de posiciones',
          error: error,
          stackTrace: stackTrace,
        );
        _isTracking = false;
        _positionSub?.cancel();
        _positionSub = null;
        if (!_locationController.isClosed) {
          _locationController.addError(error, stackTrace);
        }
      },
      onDone: () {
        logDebug('Stream de geolocalización finalizado');
        _isTracking = false;
        _positionSub?.cancel();
        _positionSub = null;
      },
    );
  }

  Future<void> updateSettings(LocationSettings newSettings) async {
    if (!_isTracking) return;
    logDebug('Actualizando configuración de tracking...');
    await _startStream(newSettings);
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _isTracking = false;
    await GetIt.I<ForegroundServiceManager>().stopService();
  }

  Future<LocationPoint?> getCurrentOnce() async {
    final ok = await _ensurePermissions();
    if (!ok) {
      logDebug('Permisos insuficientes para obtener posición actual');
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
    logDebug(
      'Posición actual obtenida',
      details: 'lat=${pos.latitude}, lng=${pos.longitude}',
    );
    return LocationPoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: pos.timestamp.toUtc(),
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      speed: pos.speed,
      heading: pos.heading,
    );
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:51 UTC-5 (Lima)][desc: Escucha EventChannel nativo iOS (LocationTracker.swift) y reenvía puntos al stream existente][obj: LocationService.startNativeListener]
  Future<void> startNativeListener() async {
    if (!Platform.isIOS) return;
    await _nativeSub?.cancel();
    const channel = EventChannel('pe.gob.onp.thaqhiri/location_stream');
    _nativeSub = channel.receiveBroadcastStream().listen(
      (data) {
        if (data is Map && !_locationController.isClosed) {
          final point = LocationPoint(
            latitude: (data['latitude'] as num).toDouble(),
            longitude: (data['longitude'] as num).toDouble(),
            timestamp: DateTime.parse(data['timestamp'] as String),
            accuracy: (data['accuracy'] as num?)?.toDouble(),
            altitude: (data['altitude'] as num?)?.toDouble(),
            speed: (data['speed'] as num?)?.toDouble(),
            heading: (data['heading'] as num?)?.toDouble(),
          );
          logDebug(
            'Punto nativo iOS recibido',
            details: 'lat=${point.latitude}, lng=${point.longitude}',
          );
          _locationController.add(point);
        }
      },
      onError: (error) {
        logError('Error en EventChannel nativo iOS', error: error);
      },
    );
    logDebug('Listener nativo iOS iniciado');
  }

  Future<void> stopNativeListener() async {
    await _nativeSub?.cancel();
    _nativeSub = null;
    logDebug('Listener nativo iOS detenido');
  }

  void dispose() {
    _positionSub?.cancel();
    _nativeSub?.cancel();
    _isTracking = false;
    _locationController.close();
  }
}
