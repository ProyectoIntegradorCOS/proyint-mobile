// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 14:00 UTC-5 (Lima)][desc: Widget extraído para resumen de jornada][obj: JourneySummaryDialog]
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:15 UTC-5 (Lima)][desc: Corrige imports de modelos y servicios][obj: JourneySummaryDialog imports]
import 'package:flutter/material.dart';
import '../../../../models/assigned_visit.dart';
import '../../../../services/audit_service.dart';

class JourneySummaryDialog extends StatefulWidget {
  final List<AssignedVisit> visits;
  final Set<String> completedIds;

  const JourneySummaryDialog({
    super.key,
    required this.visits,
    required this.completedIds,
  });

  @override
  State<JourneySummaryDialog> createState() => _JourneySummaryDialogState();
}

class _JourneySummaryDialogState extends State<JourneySummaryDialog> {
  String _durationLabel = 'Calculando...';

  @override
  void initState() {
    super.initState();
    _calculateDuration();
  }

  Future<void> _calculateDuration() async {
    String fmt(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    DateTime? startAt;
    DateTime endAt = DateTime.now();
    try {
      final events = await AuditService.instance.getEvents();
      // Find earliest relevant event of today
      final today = DateTime.now();
      final dayStart = DateTime(today.year, today.month, today.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      for (final e in events) {
        final ts = DateTime.tryParse(e['timestamp'] as String? ?? '');
        if (ts == null) continue;
        if (ts.isBefore(dayStart) || !ts.isBefore(dayEnd)) continue;
        final type = e['type'] as String? ?? '';
        if (type == 'arrival' || type == 'start_verification') {
          if (startAt == null || ts.isBefore(startAt)) startAt = ts;
        }
      }
    } catch (_) {}
    
    if (mounted) {
      setState(() {
        _durationLabel = startAt != null
            ? '${fmt(startAt)} - ${fmt(endAt)} (${endAt.difference(startAt).inMinutes} min)'
            : 'Duración: N/D';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.visits.length;
    final completed = widget.completedIds.length;

    final summaryLines = <String>[
      'Jornada finalizada',
      'Completadas: $completed / $total',
      _durationLabel,
      '',
      'Visitas:',
      ...widget.visits.map(
        (v) => '${widget.completedIds.contains(v.id) ? '[x]' : '[ ]'} ${v.name}',
      ),
    ];
    final summaryText = summaryLines.join('\n');

    return AlertDialog(
      title: const Text('¡Todo listo!'),
      content: SingleChildScrollView(
        child: Text(summaryText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
