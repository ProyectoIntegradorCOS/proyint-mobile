import '../models/assigned_visit.dart';

class MockScheduleService {
  Future<List<AssignedVisit>> fetchTodayVisits() async {
    // Simulated network delay
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Ejemplo práctico solicitado
    // Horario de hoy en zona local
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return [
      AssignedVisit(
        id: 'visit_mintra',
        name: 'Ministerio de Trabajo del Perú',
        address: 'Av. Salaverry 655, Jesús María, Lima',
        latitude: -12.07159, // aproximado
        longitude: -77.04052,
        peopleToVerify: 10,
        confirmed: true,
        scheduledAt: DateTime(today.year, today.month, today.day, 10, 0),
        toleranceMinutes: 10,
        contactName: 'Mesa de Partes',
        contactPhone: '+51 1 315 7100',
        notes: 'Ingreso por puerta principal, llevar credencial.',
      ),
      AssignedVisit(
        id: 'visit_sunat',
        name: 'SUNAT',
        address: 'Av. Garcilaso de la Vega 1472, Cercado de Lima',
        latitude: -12.05923, // aproximado
        longitude: -77.03816,
        peopleToVerify: 1,
        confirmed: false,
        contactName: 'Recepción',
        contactPhone: '+51 1 315 0730',
        notes: 'Solicitar pase temporal en recepción.',
      ),
      AssignedVisit(
        id: 'visit_petroperu',
        name: 'PETROPERÚ',
        address: 'Av. Enrique Canaval Moreyra 150, San Isidro',
        latitude: -12.09703, // aproximado
        longitude: -77.02469,
        peopleToVerify: 5,
        confirmed: false,
        contactName: 'Seguridad Edificio',
        contactPhone: '+51 1 614 5000',
        notes: 'Ingreso por estacionamiento lateral.',
      ),
    ];
  }
}
