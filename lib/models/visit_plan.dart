enum VisitItemState {
  pending,
  enRoute,
  onSite,
  inVisit,
  done,
  cancelled;

  static VisitItemState fromApi(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'EN_ROUTE':
        return VisitItemState.enRoute;
      case 'ON_SITE':
        return VisitItemState.onSite;
      case 'IN_VISIT':
        return VisitItemState.inVisit;
      case 'DONE':
        return VisitItemState.done;
      case 'CANCELLED':
        return VisitItemState.cancelled;
      case 'PENDING':
      default:
        return VisitItemState.pending;
    }
  }

  String get apiValue {
    switch (this) {
      case VisitItemState.pending:
        return 'PENDING';
      case VisitItemState.enRoute:
        return 'EN_ROUTE';
      case VisitItemState.onSite:
        return 'ON_SITE';
      case VisitItemState.inVisit:
        return 'IN_VISIT';
      case VisitItemState.done:
        return 'DONE';
      case VisitItemState.cancelled:
        return 'CANCELLED';
    }
  }

  String get label {
    switch (this) {
      case VisitItemState.pending:
        return 'Pendiente';
      case VisitItemState.enRoute:
        return 'En ruta';
      case VisitItemState.onSite:
        return 'En lugar';
      case VisitItemState.inVisit:
        return 'En visita';
      case VisitItemState.done:
        return 'Completada';
      case VisitItemState.cancelled:
        return 'Cancelada';
    }
  }
}

class VisitPlan {
  VisitPlan({
    required this.id,
    required this.title,
    required this.plannedFor,
    required this.status,
    required this.supervisorId,
    required this.verifierId,
    required this.items,
  });

  final int id;
  final String? title;
  final DateTime? plannedFor;
  final String status;
  final int supervisorId;
  final int verifierId;
  final List<VisitItem> items;

  VisitPlan copyWith({String? status, List<VisitItem>? items}) {
    return VisitPlan(
      id: id,
      title: title,
      plannedFor: plannedFor,
      status: status ?? this.status,
      supervisorId: supervisorId,
      verifierId: verifierId,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'plannedFor': plannedFor?.toIso8601String(),
      'status': status,
      'supervisorId': supervisorId,
      'verifierId': verifierId,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  factory VisitPlan.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List<dynamic>? ?? [])
        .map((e) => VisitItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return VisitPlan(
      id: _toInt(json['id']),
      title: json['title'] as String?,
      plannedFor: json['plannedFor'] != null
          ? DateTime.tryParse(json['plannedFor'] as String)
          : null,
      status: json['status'] as String? ?? 'PLANNED',
      supervisorId: _toInt(json['supervisorId']),
      verifierId: _toInt(json['verifierId']),
      items: list,
    );
  }
}

class VisitItem {
  VisitItem({
    required this.id,
    required this.companyName,
    required this.targetTime,
    required this.orderIndex,
    required this.state,
    required this.startTime,
    required this.endTime,
    this.prioridad,
    this.plantillaPv,
    this.latitude,
    this.longitude,
    this.address,
    this.complex,
    this.foundProblem,
    this.problemNote,
    this.otherInfo,
  });

  final int id;
  final String companyName;
  final DateTime? targetTime;
  final int orderIndex;
  final VisitItemState state;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? prioridad;
  final String? plantillaPv;
  final bool? complex;
  final bool? foundProblem;
  final String? problemNote;
  final String? otherInfo;
  final double? latitude;
  final double? longitude;
  final String? address;

  factory VisitItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? raw) =>
        raw != null && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
    return VisitItem(
      id: _toInt(json['id']),
      companyName: json['companyName'] as String? ?? 'Sin nombre',
      targetTime: parseDate(json['targetTime'] as String?),
      orderIndex: _toInt(json['orderIndex']),
      state: VisitItemState.fromApi(json['state'] as String?),
      startTime: parseDate(json['startTime'] as String?),
      endTime: parseDate(json['endTime'] as String?),
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-07 14:35 UTC-5 (Lima)][desc: Mapea prioridad del plan para respetar jerarquía en reordenamiento][obj: VisitItem.fromJson prioridad]
      prioridad: json['prioridad'] as String?,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-08 12:52 UTC-5 (Lima)][desc: Mapea plantilla del plan de visitas (DE_PLANT_PV)][obj: VisitItem.fromJson plantillaPv]
      plantillaPv: json['plantillaPv'] as String?,
      complex: json['complex'] as bool?,
      foundProblem: json['foundProblem'] as bool?,
      problemNote: json['problemNote'] as String?,
      otherInfo: json['otherInfo'] as String?,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-06 00:00 UTC-5 (Lima)][desc: Mapea lat/lng y dirección desde el API del plan de visitas (direccion + coords de destino)][obj: VisitItem.fromJson coords/address]
      latitude: _toDouble(json['latitude'] ?? json['latitud']),
      longitude: _toDouble(json['longitude'] ?? json['longitud']),
      address: (json['address'] as String?) ?? (json['direccion'] as String?),
    );
  }

  VisitItem copyWith({
    int? orderIndex,
    VisitItemState? state,
    DateTime? startTime,
    DateTime? endTime,
    bool? complex,
    bool? foundProblem,
    String? problemNote,
    String? otherInfo,
    String? prioridad,
    String? plantillaPv,
    double? latitude,
    double? longitude,
    String? address,
  }) {
    return VisitItem(
      id: id,
      companyName: companyName,
      targetTime: targetTime,
      orderIndex: orderIndex ?? this.orderIndex,
      state: state ?? this.state,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      prioridad: prioridad ?? this.prioridad,
      plantillaPv: plantillaPv ?? this.plantillaPv,
      complex: complex ?? this.complex,
      foundProblem: foundProblem ?? this.foundProblem,
      problemNote: problemNote ?? this.problemNote,
      otherInfo: otherInfo ?? this.otherInfo,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'companyName': companyName,
      'targetTime': targetTime?.toIso8601String(),
      'orderIndex': orderIndex,
      'state': state.apiValue,
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'prioridad': prioridad,
      'plantillaPv': plantillaPv,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'complex': complex,
      'foundProblem': foundProblem,
      'problemNote': problemNote,
      'otherInfo': otherInfo,
    };
  }
}

int _toInt(dynamic value) {
  if (value is num) return value.toInt();
  return 0;
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
