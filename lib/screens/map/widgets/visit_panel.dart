import 'package:flutter/material.dart';

import '../../../../models/assigned_visit.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:17 UTC (Lima)][desc: Crea panel de visita activa][obj: VisitPanel]
class VisitPanel extends StatelessWidget {
  const VisitPanel({
    super.key,
    required this.visit,
    required this.onCheckIn,
    required this.onCheckOut,
    this.onValidate,
    this.showEmpty = true,
    this.pendingCount = 0,
    this.totalCount = 0,
    this.completedCount = 0,
    this.pendingSync = false,
    this.syncing = false,
    this.pendingQuestionnaire = false,
    this.pendingQuestionnaireCount = 0,
  });

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:33 UTC (Lima)][desc: Usa AssignedVisit como modelo de visita activa][obj: VisitPanel.visit]
  final AssignedVisit? visit;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback? onValidate;
  final bool showEmpty;
  final int pendingCount;
  final int totalCount;
  final int completedCount;
  final bool pendingSync;
  final bool syncing;
  final bool pendingQuestionnaire;
  final int pendingQuestionnaireCount;

  @override
  Widget build(BuildContext context) {
    if (visit == null) {
      if (!showEmpty) return const SizedBox.shrink();
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Muestra conteo de pendientes si no hay visita activa][obj: VisitPanel._buildEmpty]
      return _buildEmpty(context);
    }
    final item = visit!;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-12 10:25 UTC-5 (Lima)][desc: Evita overflow del título y badge en el panel de visita][obj: VisitPanel.build]
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text(item.confirmed ? 'Confirmada' : 'Pendiente'),
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  labelStyle: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.address ?? 'Dirección no disponible',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (pendingSync)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Pendiente de sincronizar',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            if (syncing)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blueGrey.shade400,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sincronizando…',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.blueGrey.shade400),
                    ),
                  ],
                ),
              ),
            if (pendingQuestionnaire)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_turned_in_outlined,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      pendingQuestionnaireCount > 1
                          ? 'Cuestionario pendiente ($pendingQuestionnaireCount)'
                          : 'Cuestionario pendiente',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              children: [
                ElevatedButton.icon(
                  onPressed: onCheckIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Check-in'),
                ),
                OutlinedButton.icon(
                  onPressed: onCheckOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Check-out'),
                ),
                if (onValidate != null)
                  TextButton(
                    onPressed: onValidate,
                    child: const Text('Validar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    if (pendingCount <= 0) return const SizedBox.shrink();
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-12 10:55 UTC-5 (Lima)][desc: Mensaje dinámico de pendientes vs total][obj: VisitPanel._buildEmpty]
    final total = totalCount > 0 ? totalCount : pendingCount;
    final completed = completedCount.clamp(0, total);
    final remaining = pendingCount;
    String message;
    if (completed <= 0 || remaining == total) {
      message = remaining == 1
          ? 'Tienes 1 visita pendiente'
          : 'Tienes $remaining visitas pendientes';
    } else {
      message = 'Tienes $remaining de $total visitas pendientes';
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.route, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
