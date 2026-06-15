class UserProfile {
  UserProfile({
    this.id,
    required this.saaSubject,
    required this.usuario,
    required this.nombre,
    required this.estado,
    this.equipoId,
    this.equipoNombre,
    this.horarioId,
    this.horarioNombre,
    this.horaInicio,
    this.horaFin,
    this.email,
  });

  final int? id;
  final String saaSubject;
  final String usuario;
  final String nombre;
  final int estado;
  final int? equipoId;
  final String? equipoNombre;
  final int? horarioId;
  final String? horarioNombre;
  final int? horaInicio;
  final int? horaFin;
  final String? email;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int?,
      saaSubject: json['saaSubject'] as String? ?? '',
      usuario: json['usuario'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      estado: json['estado'] as int? ?? 0,
      equipoId: (json['equipoId'] as num?)?.toInt(),
      equipoNombre: json['equipoNombre'] as String?,
      horarioId: (json['horarioId'] as num?)?.toInt(),
      horarioNombre: json['horarioNombre'] as String?,
      horaInicio: (json['horaInicio'] as num?)?.toInt(),
      horaFin: (json['horaFin'] as num?)?.toInt(),
      email: json['email'] as String?,
    );
  }
}

class EquipoOption {
  EquipoOption({required this.id, required this.nombre});
  final int id;
  final String nombre;

  factory EquipoOption.fromJson(Map<String, dynamic> json) {
    return EquipoOption(
      id: (json['id'] as num).toInt(),
      nombre: json['nombre'] as String? ?? '',
    );
  }
}

class HorarioOption {
  HorarioOption({required this.id, required this.nombre, required this.horaInicio, required this.horaFin});
  final int id;
  final String nombre;
  final int horaInicio;
  final int horaFin;

  factory HorarioOption.fromJson(Map<String, dynamic> json) {
    return HorarioOption(
      id: (json['id'] as num).toInt(),
      nombre: json['nombre'] as String? ?? '',
      horaInicio: (json['horaInicio'] as num?)?.toInt() ?? 0,
      horaFin: (json['horaFin'] as num?)?.toInt() ?? 0,
    );
  }
}
