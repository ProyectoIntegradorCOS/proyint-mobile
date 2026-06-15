import 'package:flutter/material.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 15:10 UTC-5 (Lima)][desc: Widget para overlay de espera en destino][obj: DwellOverlay]
class DwellOverlay extends StatelessWidget {
  final DateTime dwellEndsAt;
  final double arrivalRadius;
  final VoidCallback onStartVerification;

  const DwellOverlay({
    super.key,
    required this.dwellEndsAt,
    required this.arrivalRadius,
    required this.onStartVerification,
  });

  String _formatRemaining(DateTime endsAt) {
    final now = DateTime.now();
    if (now.isAfter(endsAt)) return '00:00';
    final diff = endsAt.difference(now);
    final m = diff.inMinutes.toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('En espera en el destino'),
                  const SizedBox(height: 4),
                  // Note: This widget needs to rebuild periodically to update the timer.
                  // Since MapScreen rebuilds often or we can use a StreamBuilder/Timer here.
                  // For now, assuming parent rebuilds or it's static enough.
                  // Ideally use a TimerBuilder or StreamBuilder.
                  StreamBuilder(
                    stream: Stream.periodic(const Duration(seconds: 1)),
                    builder: (context, snapshot) {
                      return Text(
                        'Tiempo restante: ${_formatRemaining(dwellEndsAt)} • Radio: ${arrivalRadius.toStringAsFixed(0)} m',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: onStartVerification,
              child: const Text('Iniciar ahora'),
            ),
          ],
        ),
      ),
    );
  }
}
