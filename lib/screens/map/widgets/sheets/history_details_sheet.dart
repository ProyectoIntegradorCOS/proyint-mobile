// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 13:40 UTC-5 (Lima)][desc: Widget extraído para detalle de historial][obj: HistoryDetailsSheet]
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import '../../../../models/location_point.dart';
import '../history_list.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:30 UTC-5 (Lima)][desc: Agrega campo onPointSelected faltante][obj: HistoryDetailsSheet.onPointSelected]
class HistoryDetailsSheet extends StatefulWidget {
  final List<LocationPoint> points;
  final void Function(LocationPoint) onPointSelected;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;

  const HistoryDetailsSheet({
    super.key,
    required this.points,
    required this.onPointSelected,
    this.onLoadMore,
    this.isLoadingMore = false,
  });

  @override
  State<HistoryDetailsSheet> createState() => _HistoryDetailsSheetState();
}

class _HistoryDetailsSheetState extends State<HistoryDetailsSheet> {
  final Map<String, String> _addressCache = {};
  final Map<String, Future<String>> _addressFutureCache = {};

  String _formatCoordinates(LocationPoint p) {
    return '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
  }

  String _coordinateKey(LocationPoint p) {
    return '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Formatea hora local HH:mm para que la lista se vea limpia][obj: HistoryDetailsSheet time format]
  String _fmtHour(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtDate(DateTime dt) {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 14:29 UTC-5 (Lima)][desc: Muestra fecha en el detalle de historial][obj: HistoryDetailsSheet._fmtDate]
    final l = dt.toLocal();
    final y = l.year.toString().padLeft(4, '0');
    final m = l.month.toString().padLeft(2, '0');
    final d = l.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<String> _resolveAddress(LocationPoint p) async {
    final key = _coordinateKey(p);
    if (_addressCache.containsKey(key)) return _addressCache[key]!;
    if (_addressFutureCache.containsKey(key)) return _addressFutureCache[key]!;

    final future = Future<String>(() async {
      try {
        final placemarks = await placemarkFromCoordinates(
          p.latitude,
          p.longitude,
        );
        if (placemarks.isNotEmpty) {
          final pm = placemarks.first;
          final parts = [
            pm.street,
            pm.subLocality,
            pm.locality,
          ].where((e) => e != null && e.isNotEmpty).toList();
          final addr = parts.join(', ');
          _addressCache[key] = addr;
          return addr;
        }
      } catch (_) {}
      return _formatCoordinates(p);
    });

    _addressFutureCache[key] = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No hay puntos disponibles'),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              'Detalle de historial',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: HistoryList(
                items: widget.points,
                isLoading: widget.isLoadingMore,
                onLoadMore: widget.onLoadMore,
                onSelect: widget.onPointSelected,
                itemBuilder: (context, point, index) {
                  final coordsLabel = _formatCoordinates(point);
                  return FutureBuilder<String>(
                    future: _resolveAddress(point),
                    builder: (context, snapshot) {
                      final isWaiting =
                          snapshot.connectionState == ConnectionState.waiting;
                      final address = snapshot.data;
                      final displayAddress =
                          (address != null && address.trim().isNotEmpty)
                              ? address
                              : (isWaiting
                                  ? 'Buscando dirección...'
                                  : coordsLabel);
                      final subtitleLines = <String>[
                        'Fecha: ${_fmtDate(point.timestamp)} · Hora: ${_fmtHour(point.timestamp)}',
                      ];
                      if (displayAddress != coordsLabel) {
                        subtitleLines.add(coordsLabel);
                      }
                      return ListTile(
                        leading: Text('#${index + 1}'),
                        title: Text(displayAddress),
                        subtitle: Text(subtitleLines.join(' · ')),
                        trailing: isWaiting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: () {
                          Navigator.of(context).maybePop();
                          widget.onPointSelected(point);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
