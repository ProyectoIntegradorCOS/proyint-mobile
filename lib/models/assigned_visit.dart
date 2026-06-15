class AssignedVisit {
  final String id;
  final String name;
  final String? address;
  final String? contactName;
  final String? contactPhone;
  final String? notes;
  final int peopleToVerify;
  final double latitude;
  final double longitude;
  final bool confirmed; // no movable when true
  final DateTime? scheduledAt; // cita exacta (si confirmed)
  final int toleranceMinutes; // tolerancia configuración (por visita)
  final DateTime? windowStart; // opcional si se define explícitamente
  final DateTime? windowEnd; // opcional si se define explícitamente

  const AssignedVisit({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.contactName,
    this.contactPhone,
    this.notes,
    this.peopleToVerify = 1,
    this.confirmed = false,
    this.scheduledAt,
    this.toleranceMinutes = 10,
    this.windowStart,
    this.windowEnd,
  });

  DateTime? get computedWindowStart =>
      windowStart ?? (scheduledAt != null ? scheduledAt!.subtract(Duration(minutes: toleranceMinutes)) : null);
  DateTime? get computedWindowEnd =>
      windowEnd ?? (scheduledAt != null ? scheduledAt!.add(Duration(minutes: toleranceMinutes)) : null);
}
