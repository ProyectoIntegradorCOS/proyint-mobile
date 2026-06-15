import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_application_1/services/mapbox_service.dart';

void main() {
  group('MapboxService', () {
    test('geocode parses POI results', () async {
      final client = MockClient((request) async {
        expect(request.url.host, contains('mapbox.com'));
        return http.Response(jsonEncode({
          'features': [
            {
              'id': 'poi.123',
              'properties': {
                'name': 'Estadio Nacional del Peru',
              },
              'geometry': {
                'coordinates': [-77.033, -12.067],
              },
            }
          ]
        }), 200);
      });
      final service = MapboxService(client: client, accessToken: 'pk.test');
      final results = await service.geocode('Estadio Nacional', proximity: const LatLng(-12.05, -77.05));
      expect(results, isNotEmpty);
      expect(results.first.name, contains('Estadio Nacional'));
      expect(results.first.latitude, closeTo(-12.067, 1e-3));
    });

    test('directions parses geometry and steps', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/directions/')) {
          return http.Response(jsonEncode({
            'routes': [
              {
                'distance': 1200.0,
                'duration': 600.0,
                'geometry': {
                  'coordinates': [
                    [-77.04, -12.06],
                    [-77.03, -12.07]
                  ]
                },
                'legs': [
                  {
                    'distance': 1200.0,
                    'duration': 600.0,
                    'steps': [
                      {
                        'distance': 400.0,
                        'duration': 200.0,
                        'maneuver': {'instruction': 'Gira a la derecha'}
                      }
                    ]
                  }
                ]
              }
            ]
          }), 200);
        }
        return http.Response('Not Found', 404);
      });
      final service = MapboxService(client: client, accessToken: 'pk.test');
      final result = await service.directions(
        mode: RoutingMode.walking,
        waypoints: const [LatLng(-12.06, -77.04), LatLng(-12.07, -77.03)],
      );
      expect(result.coordinates.length, 2);
      expect(result.steps.first.instruction, isNotEmpty);
      expect(result.distanceMeters, 1200.0);
      expect(result.durationSeconds, 600.0);
    });
  });
}
