import 'package:flutter/material.dart';

import '../../../../models/location_point.dart';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:17 UTC (Lima)][desc: Añade widget de historial paginado][obj: HistoryList]
class HistoryList extends StatelessWidget {
  const HistoryList({
    super.key,
    required this.items,
    required this.isLoading,
    this.error,
    this.onLoadMore,
    this.onSelect,
    this.itemBuilder,
  });

  final List<LocationPoint> items;
  final bool isLoading;
  final String? error;
  final VoidCallback? onLoadMore;
  final ValueChanged<LocationPoint>? onSelect;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 16:31 UTC (Lima)][desc: Permite personalizar render de ítems del historial][obj: HistoryList.itemBuilder]
  final Widget Function(BuildContext context, LocationPoint point, int index)?
      itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (error != null && items.isEmpty) {
      return _buildError(context, error!);
    }
    if (items.isEmpty && isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return _buildEmpty(context);
    }
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 120 &&
            onLoadMore != null &&
            !isLoading) {
          onLoadMore!.call();
        }
        return false;
      },
      child: ListView.separated(
        itemCount: items.length + (isLoading ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final point = items[index];
          if (itemBuilder != null) {
            return itemBuilder!(context, point, index);
          }
          return ListTile(
            leading: const Icon(Icons.location_on),
            title: Text(
              'Lat: ${point.latitude.toStringAsFixed(5)}, Lng: ${point.longitude.toStringAsFixed(5)}',
            ),
            subtitle: Text(
              point.timestamp.toLocal().toString(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: onSelect != null ? () => onSelect!(point) : null,
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Text(
        'Sin ubicaciones en el rango seleccionado',
        style:
            Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.red),
          ),
          if (onLoadMore != null)
            TextButton(
              onPressed: onLoadMore,
              child: const Text('Reintentar'),
            ),
        ],
      ),
    );
  }
}
