import 'package:flutter/material.dart';
import '../../models/assigned_visit.dart';
import 'package:latlong2/latlong.dart' as ll;

class AssignedVisitsScreen extends StatefulWidget {
  final List<AssignedVisit> initialVisits;
  final Set<String>? completedIds;

  const AssignedVisitsScreen({
    super.key,
    required this.initialVisits,
    this.completedIds,
  });

  @override
  State<AssignedVisitsScreen> createState() => _AssignedVisitsScreenState();
}

class _AssignedVisitsScreenState extends State<AssignedVisitsScreen> {
  late List<AssignedVisit> _visits;
  bool _optimizing = false;
  late final Set<String> _completedIds;

  @override
  void initState() {
    super.initState();
    _visits = List.of(widget.initialVisits);
    _completedIds = {...?widget.completedIds};
  }

  bool _isLocked(int index) => _visits[index].confirmed || _completedIds.contains(_visits[index].id);

  Future<void> _optimizeFreeBlocks() async {
    if (_optimizing) return;
    setState(() => _optimizing = true);
    try {
      // Find anchor indices (confirmed visits)
      final anchors = <int>[];
      for (var i = 0; i < _visits.length; i++) {
        if (_visits[i].confirmed) anchors.add(i);
      }

      // Helper to compute distance (km)
      final dist = ll.Distance();
      double d(AssignedVisit a, AssignedVisit b) =>
          dist.as(ll.LengthUnit.Kilometer, ll.LatLng(a.latitude, a.longitude), ll.LatLng(b.latitude, b.longitude));

      // Optimize block between indices (exclusive) using nearest-neighbor
      void optimizeBlock(int startExclusive, int endExclusive) {
        final start = startExclusive + 1;
        final end = endExclusive - 1;
        if (start > end) return; // empty block
        final indices = <int>[];
        for (var i = start; i <= end; i++) {
          if (!_visits[i].confirmed) indices.add(i);
        }
        if (indices.length < 2) return;

        // Determine starting reference: previous anchor if exists, else first in block
        AssignedVisit ref;
        if (startExclusive >= 0) {
          ref = _visits[startExclusive];
        } else {
          ref = _visits[indices.first];
        }

        final remaining = indices.map((i) => i).toSet();
        final ordered = <int>[];
        while (remaining.isNotEmpty) {
          int? bestIdx;
          double bestDist = double.infinity;
          for (final i in remaining) {
            final di = d(ref, _visits[i]);
            if (di < bestDist) {
              bestDist = di;
              bestIdx = i;
            }
          }
          final chosen = bestIdx!;
          ordered.add(chosen);
          ref = _visits[chosen];
          remaining.remove(chosen);
        }

        // Rebuild list segment according to 'ordered'
        final originals = ordered.map((i) => _visits[i]).toList();
        var write = start;
        for (final v in originals) {
          _visits[write++] = v;
        }
      }

      if (anchors.isEmpty) {
        optimizeBlock(-1, _visits.length);
      } else {
        // Before first anchor
        optimizeBlock(-1, anchors.first);
        // Between anchors
        for (var i = 0; i < anchors.length - 1; i++) {
          optimizeBlock(anchors[i], anchors[i + 1]);
        }
        // After last anchor
        optimizeBlock(anchors.last, _visits.length);
      }

      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paradas no confirmadas optimizadas.')),
      );
    } finally {
      if (mounted) setState(() => _optimizing = false);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (_isLocked(oldIndex)) return; // can't move locked item
    if (newIndex > oldIndex) newIndex -= 1;
    // If target position is a locked item, find nearest unlocked slot
    if (newIndex >= 0 && newIndex < _visits.length && _isLocked(newIndex)) {
      // try place after the locked block
      int forward = newIndex;
      while (forward < _visits.length && _isLocked(forward)) {
        forward++;
      }
      if (forward < _visits.length) {
        newIndex = forward;
      } else {
        // try before the locked block
        int backward = newIndex - 1;
        while (backward >= 0 && _isLocked(backward)) {
          backward--;
        }
        if (backward >= 0) {
          newIndex = backward;
        } else {
          return; // nowhere to drop
        }
      }
    }
    final item = _visits.removeAt(oldIndex);
    _visits.insert(newIndex, item);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programación de hoy'),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Confirma el orden de tus visitas. Las visitas con cita confirmada no pueden moverse.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _optimizing ? null : _optimizeFreeBlocks,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Optimizar no confirmadas'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              buildDefaultDragHandles: false,
              onReorder: _onReorder,
              itemCount: _visits.length,
              itemBuilder: (context, index) {
                final v = _visits[index];
                final locked = _isLocked(index);
                final isDone = _completedIds.contains(v.id);
                final ws = v.computedWindowStart;
                final we = v.computedWindowEnd;
                final hasWindow = ws != null && we != null;
                return Card(
                  key: ValueKey(v.id),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: SizedBox(
                      width: 44,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_visits[index].confirmed)
                                const Icon(Icons.lock, size: 14, color: Colors.grey),
                              if (isDone)
                                const Padding(
                                  padding: EdgeInsets.only(left: 2),
                                  child: Icon(Icons.check_circle, size: 14, color: Colors.green),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    title: Text(
                      v.name,
                      style: isDone
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (v.address != null) Text(v.address!),
                        Text('Personas a verificar: ${v.peopleToVerify}'),
                        if (v.contactName != null || v.contactPhone != null)
                          Text('Contacto: ${v.contactName ?? '-'} ${v.contactPhone != null ? '• ${v.contactPhone}' : ''}'),
                        if (hasWindow)
                          Text('Ventana: ${_formatTime(ws!)} – ${_formatTime(we!)}')
                        else if (v.scheduledAt != null)
                          Text('Cita: ${_formatTime(v.scheduledAt!)} (±${v.toleranceMinutes}m)'),
                        if (v.notes != null) Text('Notas: ${v.notes!}'),
                      ],
                    ),
                    trailing: locked
                        ? const SizedBox(width: 24)
                        : ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_indicator),
                          ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final error = _validateOrder(_visits);
                        if (error != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(error)));
                          return;
                        }
                        Navigator.of(context).pop<List<AssignedVisit>>(_visits);
                      },
                      child: const Text('Validar e iniciar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String? _validateOrder(List<AssignedVisit> visits) {
    // Validación básica: citas confirmadas deben respetar orden cronológico
    final confirmed = <MapEntry<int, AssignedVisit>>[];
    for (var i = 0; i < visits.length; i++) {
      final v = visits[i];
      if (v.confirmed && v.scheduledAt != null) {
        confirmed.add(MapEntry(i, v));
      }
    }
    for (var i = 1; i < confirmed.length; i++) {
      final prev = confirmed[i - 1].value.scheduledAt!;
      final curr = confirmed[i].value.scheduledAt!;
      if (curr.isBefore(prev)) {
        return 'El orden no respeta la secuencia horaria de citas confirmadas.';
      }
    }
    return null;
  }
}
