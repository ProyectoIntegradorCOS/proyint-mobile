import 'package:flutter/material.dart';
import '../../../../services/mapbox_service.dart';

class GuidanceChoice {
  const GuidanceChoice({required this.mode, required this.drawOptimalRoute});

  final RoutingMode mode;
  final bool drawOptimalRoute;
}

class GuidanceModeSheet {
  static Future<GuidanceChoice?> show(BuildContext context, RoutingMode initialMode) async {
    return showModalBottomSheet<GuidanceChoice>(
      context: context,
      isScrollControlled: false,
      builder: (ctx) {
        RoutingMode selected = initialMode;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Modo de traslado',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<RoutingMode>(
                      value: RoutingMode.walking,
                      groupValue: selected,
                      onChanged: (v) => setModalState(() => selected = v!),
                      title: const Text('Caminando'),
                    ),
                    RadioListTile<RoutingMode>(
                      value: RoutingMode.driving,
                      groupValue: selected,
                      onChanged: (v) => setModalState(() => selected = v!),
                      title: const Text('Auto'),
                    ),
                    RadioListTile<RoutingMode>(
                      value: RoutingMode.drivingTraffic,
                      groupValue: selected,
                      onChanged: (v) => setModalState(() => selected = v!),
                      title: const Text('Bus / Auto (tráfico)'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(
                              GuidanceChoice(
                                mode: selected,
                                drawOptimalRoute: false,
                              ),
                            ),
                            child: const Text('Usar mi propia ruta'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(
                              GuidanceChoice(
                                mode: selected,
                                drawOptimalRoute: true,
                              ),
                            ),
                            child: const Text('Ruta óptima'),
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: const Text('Cancelar'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
