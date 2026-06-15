import 'package:flutter/material.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:17 UTC (Lima)][desc: Agrega banner de estado de tracking/sync][obj: StatusBanner]
enum TrackingStatus {
  active,
  paused,
  offline,
  syncing,
  error,
  idle,
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.status,
    this.message,
    this.onRetry,
    this.onOpenSettings,
  });

  final TrackingStatus status;
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final (textColor, bgColor, icon) = _styleFor(status, context);
    final text = message ?? _defaultMessage(status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: textColor),
            ),
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          if (onOpenSettings != null)
            IconButton(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings),
              tooltip: 'Ajustes',
            ),
        ],
      ),
    );
  }

  (Color, Color, IconData) _styleFor(TrackingStatus status, BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    switch (status) {
      case TrackingStatus.active:
        return (Colors.green.shade700, Colors.green.shade50, Icons.play_arrow);
      case TrackingStatus.syncing:
        return (
          theme.secondary,
          theme.secondary.withOpacity(0.08),
          Icons.sync,
        );
      case TrackingStatus.paused:
        final c = theme.tertiary ?? Colors.amber;
        return (c, c.withOpacity(0.12), Icons.pause_circle);
      case TrackingStatus.offline:
        return (
          Colors.orange.shade700,
          Colors.orange.shade50,
          Icons.wifi_off,
        );
      case TrackingStatus.error:
        return (theme.error, theme.error.withOpacity(0.1), Icons.error);
      case TrackingStatus.idle:
      default:
        return (
          Colors.red.shade700,
          Colors.red.shade50,
          Icons.stop_circle,
        );
    }
  }

  String _defaultMessage(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.active:
        return 'Sistema activo';
      case TrackingStatus.syncing:
        return 'Sincronizando ubicaciones...';
      case TrackingStatus.paused:
        return 'Tracking en pausa';
      case TrackingStatus.offline:
        return 'Sin conexión. Se guardan ubicaciones en el dispositivo.';
      case TrackingStatus.error:
        return 'Error de tracking o sincronización.';
      case TrackingStatus.idle:
      default:
        return 'Sesión cerrada / sistema inactivo.';
    }
  }
}
