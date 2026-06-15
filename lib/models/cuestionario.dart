// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:25 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: Questionnaire models]
class Cuestionario {
  Cuestionario({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.estado,
    this.idEquipo,
    this.nombreEquipo,
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final int? estado;
  final int? idEquipo;
  final String? nombreEquipo;

  factory Cuestionario.fromJson(Map<String, dynamic> json) {
    return Cuestionario(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: json['nombre'] as String? ?? '',
      descripcion: json['descripcion'] as String?,
      estado: (json['estado'] as num?)?.toInt(),
      idEquipo: (json['idEquipo'] as num?)?.toInt(),
      nombreEquipo: json['nombreEquipo'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'estado': estado,
      'idEquipo': idEquipo,
      'nombreEquipo': nombreEquipo,
    };
  }
}

class Pregunta {
  Pregunta({
    required this.id,
    required this.descripcion,
    required this.tipo,
    required this.obligatorio,
    required this.orden,
    this.idCuestionario,
    this.grupo,
    this.estado,
    this.idSiguientePregunta,
    this.opciones = const <Opcion>[],
  });

  final int id;
  final int? idCuestionario;
  final String descripcion;
  final String tipo;
  final String obligatorio;
  final int orden;
  final String? grupo;
  final int? estado;
  final int? idSiguientePregunta;
  final List<Opcion> opciones;

  factory Pregunta.fromJson(Map<String, dynamic> json) {
    final opcionesJson = json['opciones'] as List<dynamic>?;
    return Pregunta(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idCuestionario: (json['idCuestionario'] as num?)?.toInt(),
      descripcion: json['descripcion'] as String? ?? '',
      tipo: json['tipo'] as String? ?? '',
      obligatorio: json['obligatorio'] as String? ?? 'N',
      orden: (json['orden'] as num?)?.toInt() ?? 0,
      grupo: json['grupo'] as String?,
      estado: (json['estado'] as num?)?.toInt(),
      idSiguientePregunta: (json['idSiguientePregunta'] as num?)?.toInt(),
      opciones: opcionesJson == null
          ? const <Opcion>[]
          : opcionesJson
              .map((e) => Opcion.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'idCuestionario': idCuestionario,
      'descripcion': descripcion,
      'tipo': tipo,
      'obligatorio': obligatorio,
      'orden': orden,
      'grupo': grupo,
      'estado': estado,
      'idSiguientePregunta': idSiguientePregunta,
      'opciones': opciones.map((o) => o.toJson()).toList(),
    };
  }
}

class Opcion {
  Opcion({
    required this.id,
    required this.descripcion,
    this.idPregunta,
    this.valor,
    this.orden,
    this.estado,
    this.idSiguientePregunta,
  });

  final int id;
  final int? idPregunta;
  final String descripcion;
  final String? valor;
  final int? orden;
  final int? estado;
  final int? idSiguientePregunta;

  factory Opcion.fromJson(Map<String, dynamic> json) {
    return Opcion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idPregunta: (json['idPregunta'] as num?)?.toInt(),
      descripcion: json['descripcion'] as String? ?? '',
      valor: json['valor'] as String?,
      orden: (json['orden'] as num?)?.toInt(),
      estado: (json['estado'] as num?)?.toInt(),
      idSiguientePregunta: (json['idSiguientePregunta'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'idPregunta': idPregunta,
      'descripcion': descripcion,
      'valor': valor,
      'orden': orden,
      'estado': estado,
      'idSiguientePregunta': idSiguientePregunta,
    };
  }
}

class RespuestaPayload {
  RespuestaPayload({
    required this.idPersona,
    required this.idCuestionario,
    required this.idPregunta,
    required this.idItem,
    required this.textoPregunta,
    required this.respuesta,
    required this.estado,
  });

  final int idPersona;
  final int idCuestionario;
  final int idPregunta;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-22 09:23 UTC-5 (Lima)][desc: Envía el item de visita para asociar respuestas por visita][obj: RespuestaPayload.idItem]
  final int idItem;
  final String textoPregunta;
  final String respuesta;
  final int estado;

  Map<String, dynamic> toJson() {
    return {
      'idPersona': idPersona,
      'idCuestionario': idCuestionario,
      'idPregunta': idPregunta,
      'idItem': idItem,
      'textoPregunta': textoPregunta,
      'respuesta': respuesta,
      'estado': estado,
    };
  }
}

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:42 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: RespuestaPregunta model]
class RespuestaPregunta {
  RespuestaPregunta({required this.textoPregunta, required this.respuesta});

  final String textoPregunta;
  final String respuesta;

  factory RespuestaPregunta.fromJson(Map<String, dynamic> json) {
    return RespuestaPregunta(
      textoPregunta: json['textoPregunta'] as String? ?? '',
      respuesta: json['respuesta'] as String? ?? '',
    );
  }
}
