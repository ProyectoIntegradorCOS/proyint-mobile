import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 15:20 UTC-5 (Lima)][desc: Widget para overlay de historial][obj: HistoryOverlay]
class HistoryOverlay extends StatelessWidget {
  final int routeLength;
  final double lastDistanceKm;
  final DateTimeRange? lastHistoryRange;
  final VoidCallback onShowDetails;
  final VoidCallback onClose;

  const HistoryOverlay({
    super.key,
    required this.routeLength,
    required this.lastDistanceKm,
    required this.lastHistoryRange,
    required this.onShowDetails,
    required this.onClose,
  });

  String _formatRange(DateTimeRange range) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Muestra rango como fechas (yyyy-MM-dd) para historial por fecha][obj: HistoryOverlay._formatRange]
    final fmt = DateFormat('yyyy-MM-dd');
    final startLocal = range.start.toLocal();
    final endLocal = range.end.toLocal();
    return '${fmt.format(startLocal)} - ${fmt.format(endLocal)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Historial (${lastHistoryRange != null ? _formatRange(lastHistoryRange!) : 'N/A'})',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Botón para cerrar overlay de historial][obj: HistoryOverlay close]
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Distancia total: ${lastDistanceKm.toStringAsFixed(2)} km',
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Puntos: $routeLength'),
                TextButton.icon(
                  onPressed: onShowDetails,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Ver detalle'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
