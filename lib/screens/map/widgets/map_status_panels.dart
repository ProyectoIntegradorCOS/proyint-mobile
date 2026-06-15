// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:15 UTC-5 (Lima)][desc: Corrige imports de widgets][obj: MapStatusPanels imports]
import 'package:flutter/material.dart';
import 'status_banner.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 14:40 UTC-5 (Lima)][desc: Widget para paneles de estado y overlays][obj: MapStatusPanels]
class MapStatusPanels extends StatelessWidget {
  final bool waitingInitialFix;
  final String? shutdownMessage;
  final String? connectionMessage;
  final VoidCallback onRetryConnection;

  const MapStatusPanels({
    super.key,
    required this.waitingInitialFix,
    required this.shutdownMessage,
    required this.connectionMessage,
    required this.onRetryConnection,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (waitingInitialFix)
          Positioned(
            top: 24,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.blueGrey.shade700.withValues(alpha: 0.9),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Obteniendo tu ubicación...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (shutdownMessage != null)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          shutdownMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (connectionMessage != null)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        StatusBanner(
                          status: TrackingStatus.offline,
                          message: connectionMessage,
                          onRetry: onRetryConnection,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
