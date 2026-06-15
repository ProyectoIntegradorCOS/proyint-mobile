import 'package:flutter/material.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:17 UTC (Lima)][desc: Agrega chip informativo de tracking][obj: TrackingInfoChip]
class TrackingInfoChip extends StatelessWidget {
  const TrackingInfoChip({
    super.key,
    this.accuracy,
    this.speed,
    this.lastFix,
    this.scheduleLabel,
    this.filterDecision,
    this.pendingLocalCount,
    this.lastSyncOkAt,
    this.backendAvailable,
    this.bgFlushAt,
    this.bgFlushStatus,
  });

  final double? accuracy;
  final double? speed;
  final DateTime? lastFix;
  final String? scheduleLabel;
  final String? filterDecision;
  final int? pendingLocalCount;
  final DateTime? lastSyncOkAt;
  final bool? backendAvailable;
  final DateTime? bgFlushAt;
  final String? bgFlushStatus;

  @override
  Widget build(BuildContext context) {
    final parts = _buildParts();
    final color = Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.8);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:57 UTC-5 (Lima)][desc: Usa layout con Wrap para permitir salto de línea en pantallas angostas][obj: TrackingInfoChip responsive layout]
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.location_searching, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: parts
                      .map((text) => Text(
                            text,
                            style: Theme.of(context).textTheme.bodySmall,
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<String> _buildParts() {
    final parts = <String>[];
    if (accuracy != null) {
      parts.add('Accuracy: ${accuracy!.toStringAsFixed(1)} m');
    }
    if (speed != null) {
      parts.add('Speed: ${speed!.toStringAsFixed(1)} m/s');
    }
    if (lastFix != null) {
      final ageSec = DateTime.now().difference(lastFix!).inSeconds;
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-13 15:37 UTC-5 (Lima)][desc: Muestra antigüedad del último fix para diagnóstico][obj: TrackingInfoChip age]
      parts.add('Age: ${ageSec}s');
      parts.add('Fix: ${lastFix!.toLocal()}');
    }
    if (scheduleLabel != null && scheduleLabel!.isNotEmpty) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-13 15:52 UTC-5 (Lima)][desc: Muestra horario laboral permitido en chip de tracking][obj: TrackingInfoChip schedule]
      parts.add('Horario: $scheduleLabel');
    }
    if (filterDecision != null && filterDecision!.isNotEmpty) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 10:45 UTC-5 (Lima)][desc: Muestra la última decisión de filtro en chip de tracking][obj: TrackingInfoChip filterDecision]
      parts.add('Filtro: $filterDecision');
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 12:13 UTC-5 (Lima)][desc: Muestra cantidad de ubicaciones pendientes locales para validar vaciado de SQLite desde UI][obj: TrackingInfoChip pending count]
    if (pendingLocalCount != null) {
      parts.add('Pendientes locales: $pendingLocalCount');
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 12:13 UTC-5 (Lima)][desc: Expone disponibilidad de backend y hora del último sync exitoso para pruebas funcionales][obj: TrackingInfoChip sync diagnostics]
    if (backendAvailable != null) {
      parts.add('Backend: ${backendAvailable! ? 'OK' : 'Sin conexión'}');
    }
    if (lastSyncOkAt != null) {
      parts.add('Últ. sync OK: ${_formatTime(lastSyncOkAt!)}');
    }
    if (bgFlushAt != null || (bgFlushStatus != null && bgFlushStatus!.isNotEmpty)) {
      final ageSec = bgFlushAt != null
          ? DateTime.now().difference(bgFlushAt!).inSeconds
          : null;
      final status = _formatFlushStatus(bgFlushStatus);
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-02-19 11:45 UTC-5 (Lima)][desc: Muestra estado y antigüedad del último flush nativo en background][obj: TrackingInfoChip bgFlush]
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 12:13 UTC-5 (Lima)][desc: Aclara que el texto corresponde al último flush nativo y no al estado vivo de sincronización][obj: TrackingInfoChip bgFlush label]
      if (status != null && ageSec != null) {
        parts.add('Últ. flush nativo: $status (${ageSec}s)');
      } else if (status != null) {
        parts.add('Últ. flush nativo: $status');
      } else if (ageSec != null) {
        parts.add('Últ. flush nativo: ${ageSec}s');
      }
    }
    if (parts.isEmpty) {
      parts.add('Sin datos de tracking');
    }
    return parts;
  }

  String? _formatFlushStatus(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'start') return 'Enviado';
    if (raw == 'empty') return 'Sin pendientes';
    if (raw == 'error') return 'Error';
    if (raw.startsWith('ok:')) {
      final count = raw.substring(3);
      return 'OK ($count)';
    }
    return raw;
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}
