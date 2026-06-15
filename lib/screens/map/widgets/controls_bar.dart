import 'package:flutter/material.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:17 UTC (Lima)][desc: Añade barra de controles rápidos de mapa/tracking][obj: ControlsBar]
class ControlsBar extends StatelessWidget {
  const ControlsBar({
    super.key,
    required this.isTracking,
    required this.onToggleTracking,
    this.onCenterOnUser,
    this.onToggleFilters,
    this.filtersActive = false,
  });

  final bool isTracking;
  final bool filtersActive;
  final VoidCallback onToggleTracking;
  final VoidCallback? onCenterOnUser;
  final VoidCallback? onToggleFilters;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onToggleTracking,
            icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
            label: Text(isTracking ? 'Detener' : 'Iniciar'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onCenterOnUser,
          icon: const Icon(Icons.my_location),
          tooltip: 'Centrar en mi ubicación',
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: onToggleFilters,
          icon: Icon(filtersActive ? Icons.filter_alt_off : Icons.filter_alt),
          tooltip: filtersActive ? 'Quitar filtros' : 'Aplicar filtros',
        ),
      ],
    );
  }
}
