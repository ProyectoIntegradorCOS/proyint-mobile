import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/background_schedule_manager.dart';
import '../../services/identity_service.dart';
import '../../models/user_profile.dart';
import '../../utils/logger.dart';
import '../../services/logout_flush_service.dart';
import '../map/map_screen.dart';
import 'auth_gate.dart';

class UserSetupScreen extends StatefulWidget {
  const UserSetupScreen({super.key, required this.session});

  final UserSession session;

  @override
  State<UserSetupScreen> createState() => _UserSetupScreenState();
}

class _UserSetupScreenState extends State<UserSetupScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<EquipoOption> _equipos = const [];
  List<HorarioOption> _horarios = const [];
  EquipoOption? _selectedEquipo;
  HorarioOption? _selectedHorario;
  UserProfile? _existing;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.updateAuthToken(widget.session.token);
      final results = await Future.wait([
        _api.fetchEquiposActivos(),
        _api.fetchHorarios(),
        _api.fetchUserProfile(widget.session.uid),
      ]);
      final equipos = results[0] as List<EquipoOption>;
      final horarios = results[1] as List<HorarioOption>;
      final user = results[2] as UserProfile?;
      setState(() {
        _equipos = equipos;
        _horarios = horarios;
        _existing = user;
        _selectedEquipo = _findEquipo(equipos, user?.equipoId);
        _selectedHorario = _findHorario(horarios, user?.horarioId);
        _selectedEquipo ??= equipos.isNotEmpty ? equipos.first : null;
        _selectedHorario ??= horarios.isNotEmpty ? horarios.first : null;
      });
      if (_selectedHorario != null) {
        await GetIt.I<IdentityService>().setHorario(
          inicio: _selectedHorario!.horaInicio,
          fin: _selectedHorario!.horaFin,
        );
      }
    } catch (e, st) {
      logError('Error cargando catálogos/usuario', error: e, stackTrace: st);
      setState(() => _error = 'No se pudieron cargar los datos: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      } else {
        _loading = false;
      }
    }
  }

  Future<void> _save() async {
    if (_selectedEquipo == null) {
      setState(() => _error = 'Selecciona un equipo');
      return;
    }
    if (_selectedHorario == null) {
      setState(() => _error = 'Selecciona un horario');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.saveUserProfile(
        id: _existing?.id,
        saaSubject: widget.session.uid,
        usuario: widget.session.usuario,
        nombre: widget.session.nombre,
        estado: 1,
        equipoId: _selectedEquipo!.id,
        horarioId: _selectedHorario!.id,
        email: widget.session.email,
        usuarioSesion: widget.session.usuario,
      );
      await GetIt.I<IdentityService>().setHorario(
        inicio: _selectedHorario!.horaInicio,
        fin: _selectedHorario!.horaFin,
      );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MapScreen()));
    } catch (e, st) {
      logError('Error guardando usuario', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _error = 'No se pudo guardar: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      } else {
        _saving = false;
      }
    }
  }

  Future<void> _exit() async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Envía ubicaciones pendientes antes de salir del alta de usuario][obj: UserSetupScreen._exit]
    await LogoutFlushService.flushPendingBeforeLogout(
      uid: widget.session.uid,
      token: widget.session.token,
    );
    try {
      await GetIt.I<AuthService>().signOutSaa();
    } catch (_) {
      await GetIt.I<AuthService>().signOut();
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Asegura fg_tracking_active=false antes de enforceNow en logout para permitir tracking nativo por horario][obj: UserSetupScreen._exit fg_tracking_active]
    await BackgroundScheduleManager.setForegroundTrackingActive(false);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Tras logout real, fuerza enforceNow Android para continuar tracking por horario (si aplica)][obj: UserSetupScreen._exit enforceNow]
    await BackgroundScheduleManager.enforceNow();
    await GetIt.I<IdentityService>().clearHorario();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Regresa al AuthGate al salir del alta de usuario][obj: UserSetupScreen._exit]
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  EquipoOption? _findEquipo(List<EquipoOption> list, int? id) {
    if (id == null) return null;
    for (final e in list) {
      if (e.id == id) return e;
    }
    return null;
  }

  HorarioOption? _findHorario(List<HorarioOption> list, int? id) {
    if (id == null) return null;
    for (final h in list) {
      if (h.id == id) return h;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Completa tu registro')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Verificamos tu identidad en SAA. Completa los datos para continuar.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    _ReadOnlyField(
                      label: 'Nombre completo',
                      value: session.nombre,
                    ),
                    _ReadOnlyField(label: 'Usuario', value: session.usuario),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<HorarioOption>(
                      value: _selectedHorario,
                      decoration: const InputDecoration(labelText: 'Horario'),
                      items: _horarios
                          .map(
                            (h) => DropdownMenuItem(
                              value: h,
                              child: Text(h.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedHorario = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<EquipoOption>(
                      value: _selectedEquipo,
                      decoration: const InputDecoration(labelText: 'Equipo'),
                      items: _equipos
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(e.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedEquipo = v),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar y continuar'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _saving ? null : _exit,
                      child: const Text('Salir'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        readOnly: true,
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant,
        ),
      ),
    );
  }
}
