// import 'package:firebase_auth/firebase_auth.dart'; // Comentado: usar SAA
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'secure_token_store.dart';

class IdentityService {
  IdentityService();

  // Implementación basada en SAA
  UserSession? get _session => GetIt.I<AuthService>().currentSession;

  String? get uid => _session?.uid;
  String? get email => _session?.email;
  String? get usuario => _session?.usuario;
  String? get nombre => _session?.nombre;
  bool get isSignedIn => _session != null;
  int? get horarioInicio => _horarioInicio;
  int? get horarioFin => _horarioFin;
  int? get horarioId => _horarioId;

  int? _horarioInicio;
  int? _horarioFin;
  int? _horarioId;
  bool _horarioLoaded = false;

  List<String> get permisos => _session?.permisos ?? const <String>[];
  bool hasPermiso(String codigo) {
    final target = codigo.toLowerCase();
    for (final p in permisos) {
      if (p.toLowerCase() == target) return true;
    }
    return false;
  }

  Future<String?> getIdToken() async {
    final s = _session;
    if (s != null) return s.token;
    try {
      return await SecureTokenStore.readAuthToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> setHorario({int? inicio, int? fin, int? id}) async {
    _horarioInicio = inicio;
    _horarioFin = fin;
    _horarioId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (inicio != null) await prefs.setInt('horario_inicio', inicio);
      if (fin != null) await prefs.setInt('horario_fin', fin);
      if (id != null) await prefs.setInt('horario_id', id);
    } catch (_) {}
  }

  Future<void> ensureHorarioLoaded() async {
    if (_horarioLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ini = prefs.getInt('horario_inicio');
      final fin = prefs.getInt('horario_fin');
      final id = prefs.getInt('horario_id');
      _horarioInicio = ini;
      _horarioFin = fin;
      _horarioId = id;
    } catch (_) {}
    _horarioLoaded = true;
  }

  Future<void> clearHorario() async {
    _horarioInicio = null;
    _horarioFin = null;
    _horarioId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('horario_inicio');
      await prefs.remove('horario_fin');
      await prefs.remove('horario_id');
    } catch (_) {}
  }
}
