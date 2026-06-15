// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 13:55 UTC-5 (Lima)][desc: Widget extraído para selección de capas][obj: MapLayersDialog]
import 'package:flutter/material.dart';

enum BaseLayer { streets, satellite, outdoors }

class MapLayersDialog extends StatelessWidget {
  final BaseLayer currentLayer;

  const MapLayersDialog({
    Key? key,
    required this.currentLayer,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Capas del mapa'),
      children: [
        RadioListTile<BaseLayer>(
          value: BaseLayer.streets,
          groupValue: currentLayer,
          onChanged: (v) => Navigator.of(context).pop(v),
          title: const Text('Calles'),
        ),
        RadioListTile<BaseLayer>(
          value: BaseLayer.satellite,
          groupValue: currentLayer,
          onChanged: (v) => Navigator.of(context).pop(v),
          title: const Text('Satélite'),
        ),
        RadioListTile<BaseLayer>(
          value: BaseLayer.outdoors,
          groupValue: currentLayer,
          onChanged: (v) => Navigator.of(context).pop(v),
          title: const Text('Relieve'),
        ),
      ],
    );
  }
}
