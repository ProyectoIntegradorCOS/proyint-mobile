import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../models/visit_plan.dart';
import '../../../../models/route_models.dart';

class MapDialogs {
  /// Diálogo asíncrono que alerta sobre una visita prolongada y permite al usuario finalizarla.
  static Future<String?> showVisitReminderDialog(
      BuildContext context, DateTime? activeVisitStartedAt) async {
    if (activeVisitStartedAt == null) return null;
    final elapsed = DateTime.now().difference(activeVisitStartedAt);
    final minutes = elapsed.inMinutes;

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Visita larga'),
        content: Text(
          'La visita ya lleva $minutes minutos. ¿Deseas finalizar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('ok'),
            child: const Text('Seguir'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('finish'),
            child: const Text('Finalizar visita'),
          ),
        ],
      ),
    );
  }

  /// Diálogo asíncrono para confirmar el cierre de una visita en progreso.
  static Future<bool?> showConfirmCloseVisitDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cierre'),
        content: const Text(
          '¿Confirmas que deseas cerrar la visita? Si no es así, continúa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seguir'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Muestra una alerta inteligente y activa un callback si se desea trazar ruta hacia esa alerta.
  static void showSmartAlert(
      BuildContext context, VisitItem visit, DateTime time, VoidCallback onGoNow) {
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Alerta de Cita'),
          ],
        ),
        content: Text(
          'Tienes una cita programada con "${visit.companyName}" a las $timeStr. '
          'Debes dirigirte hacia allá pronto para llegar a tiempo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onGoNow();
            },
            child: const Text('Ir ahora'),
          ),
        ],
      ),
    );
  }
}
