// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Helpers de tiempo Lima (UTC-5 fijo) para serializar timestamps con offset -05:00][obj: lima_time]

String toLimaIsoString(DateTime dt) {
  // Normalizamos al instante UTC y luego representamos ese instante en "Lima" (UTC-5).
  final utc = dt.toUtc();
  final lima = utc.subtract(const Duration(hours: 5));

  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');

  final y = lima.year.toString().padLeft(4, '0');
  final m = two(lima.month);
  final d = two(lima.day);
  final hh = two(lima.hour);
  final mm = two(lima.minute);
  final ss = two(lima.second);
  final ms = three(lima.millisecond);

  return '$y-$m-$d'
      'T$hh:$mm:$ss.$ms'
      '-05:00';
}

