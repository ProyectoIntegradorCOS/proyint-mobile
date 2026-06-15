import 'package:flutter/material.dart';
import '../../../models/visit_plan.dart';

class MapArrivalPanel extends StatelessWidget {
  const MapArrivalPanel({
    super.key,
    required this.distanceText,
    required this.isInsideArrivalZone,
    required this.arrivalConfirmed,
    required this.activePlanVisit,
    required this.showingHistory,
    required this.onConfirmArrival,
    required this.onStartVisit,
    required this.onCompleteVisit,
  });

  final String distanceText;
  final bool isInsideArrivalZone;
  final bool arrivalConfirmed;
  final VisitItem? activePlanVisit;
  final bool showingHistory;
  final VoidCallback onConfirmArrival;
  final VoidCallback onStartVisit;
  final VoidCallback onCompleteVisit;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: showingHistory ? 140 : 76,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Distancia: $distanceText m',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            
            /*if (isInsideArrivalZone &&
                !arrivalConfirmed &&
                activePlanVisit?.state != VisitItemState.onSite &&
                activePlanVisit?.state != VisitItemState.inVisit &&
                activePlanVisit?.state != VisitItemState.done)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextButton(
                  onPressed: onConfirmArrival,
                  child: const Text('Confirmar llegada'),
                ),
              ),
            if (activePlanVisit != null &&
                (arrivalConfirmed ||
                    activePlanVisit!.state == VisitItemState.onSite) &&
                activePlanVisit!.state != VisitItemState.inVisit &&
                activePlanVisit!.state != VisitItemState.done)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextButton(
                  onPressed: onStartVisit,
                  child: const Text('Iniciar visita'),
                ),
              ),
            if (activePlanVisit != null &&
                activePlanVisit!.state == VisitItemState.inVisit)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextButton(
                  onPressed: onCompleteVisit,
                  child: const Text('Completar visita'),
                ),
              ),*/
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isInsideArrivalZone &&
                    !arrivalConfirmed &&
                    activePlanVisit?.state != VisitItemState.onSite &&
                    activePlanVisit?.state != VisitItemState.inVisit &&
                    activePlanVisit?.state != VisitItemState.done)
                  TextButton(
                    onPressed: onConfirmArrival,
                    child: const Text('Confirmar llegada'),
                  ),
                if (activePlanVisit != null &&
                    (arrivalConfirmed ||
                        activePlanVisit!.state == VisitItemState.onSite) &&
                    activePlanVisit!.state != VisitItemState.inVisit &&
                    activePlanVisit!.state != VisitItemState.done)
                  TextButton(
                    onPressed: onStartVisit,
                    child: const Text('Iniciar visita'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
