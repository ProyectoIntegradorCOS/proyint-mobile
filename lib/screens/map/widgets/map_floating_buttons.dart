import 'package:flutter/material.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 14:35 UTC-5 (Lima)][desc: Widget para botones flotantes del mapa][obj: MapFloatingButtons]
class MapFloatingButtons extends StatelessWidget {
  final bool mapReady;
  final bool showingHistory;
  final bool routeActive;
  final bool dwellInProgress;
  final bool showQuickVerification;
  final bool isInsideArrivalZone;
  final bool arrivalConfirmed;
  final bool moveLayersDown;
  final VoidCallback onLayers;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onVisitPlan;
  final VoidCallback onQuickVerification;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Permite iniciar navegación nativa (Mapbox) cuando hay ruta activa][obj: MapFloatingButtons.onNavigate]
  final VoidCallback? onNavigate;

  const MapFloatingButtons({
    super.key,
    required this.mapReady,
    required this.showingHistory,
    required this.routeActive,
    required this.dwellInProgress,
    required this.showQuickVerification,
    required this.isInsideArrivalZone,
    required this.arrivalConfirmed,
    this.moveLayersDown = false,
    required this.onLayers,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onVisitPlan,
    required this.onQuickVerification,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Evita solapes moviendo botones según estado][obj: MapFloatingButtons]
    final double rightBaseBottom = moveLayersDown
        ? (dwellInProgress ? 180.0 : 140.0)
        : (dwellInProgress ? 120.0 : 56.0);
    return Stack(
      children: [
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Botón de navegación cuando hay ruta activa][obj: MapFloatingButtons navigation button]
        if (routeActive && onNavigate != null)
          Positioned(
            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:45 UTC-5 (Lima)][desc: Evita solape con botón 'Plan de visitas' cuando moveLayersDown=true][obj: MapFloatingButtons navigation button position]
            bottom: moveLayersDown
                ? (dwellInProgress ? 240 : 200)
                : (dwellInProgress ? 180 : 140),
            right: 16,
            child: FloatingActionButton.small(
              heroTag: null,
              onPressed: onNavigate,
              tooltip: 'Iniciar navegación',
              child: const Icon(Icons.navigation),
            ),
          ),
        // Botón de capas (mover a esquina superior derecha para no tapar panel)
        Positioned(
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:55 UTC-5 (Lima)][desc: Mueve el selector de capas al lado izquierdo según solicitud UX][obj: MapFloatingButtons layers button position]
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 14:23 UTC-5 (Lima)][desc: Mantiene el botón de capas en la parte superior y ajusta overlays para evitar solapes][obj: MapFloatingButtons layers button offset]
          top: 16,
          left: 16,
          child: FloatingActionButton.small(
            heroTag: null,
            onPressed: onLayers,
            tooltip: 'Capas del mapa',
            child: const Icon(Icons.layers),
          ),
        ),
        // Controles de zoom
        Positioned(
          bottom: dwellInProgress ? 120 : 32,
          left: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: null,
                onPressed: mapReady ? onZoomIn : null,
                tooltip: 'Acercar',
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: null,
                onPressed: mapReady ? onZoomOut : null,
                tooltip: 'Alejar',
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),
        // Acceso rápido al plan de visitas
        Positioned(
          bottom: rightBaseBottom,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: null,
            onPressed: onVisitPlan,
            tooltip: 'Plan de visitas',
            child: const Icon(Icons.list_alt),
          ),
        ),
        // Controles manuales rápidos
        if (showQuickVerification && !dwellInProgress)
          Positioned(
            bottom: rightBaseBottom + 56,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: null,
              onPressed: onQuickVerification,
              tooltip: isInsideArrivalZone && !arrivalConfirmed
                  ? 'Marcar llegada'
                  : 'Iniciar verificación ahora',
              child: Icon(
                isInsideArrivalZone && !arrivalConfirmed
                    ? Icons.flag
                    : Icons.play_arrow,
              ),
            ),
          ),
      ],
    );
  }
}
