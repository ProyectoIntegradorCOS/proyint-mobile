import 'dart:async';

import 'package:get_it/get_it.dart';
// import 'package:firebase_auth/firebase_auth.dart'; // Comentado: migrando a SAA
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../services/identity_service.dart';
import '../../utils/logger.dart';
import '../../services/database_service.dart';
import '../../models/user_profile.dart';
import '../../services/background_schedule_manager.dart';
import '../../services/logout_flush_service.dart';
import '../../services/location_sync_manager.dart';
import '../../services/offline_sync_manager.dart';
import '../../services/offline_sync_status.dart';
import '../../services/questionnaire_cache_store.dart';
import '../map/controllers/map_screen_controller.dart';
import 'login_screen.dart';
import '../map/map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    logDebug('AuthGate build: esperando authStateChanges');
    return StreamBuilder(
      // Stream<UserSession?>
      stream: GetIt.I<AuthService>().authStateChanges,
      builder: (context, snapshot) {
        logDebug(
          'AuthGate snapshot',
          details:
              'state=${snapshot.connectionState} hasData=${snapshot.hasData}',
        );
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          logDebug('AuthGate: sesión encontrada, navegando a RegistrationGate');
          return RegistrationGate(session: snapshot.data!);
        }
        logDebug('AuthGate: sin sesión, mostrando LoginScreen');
        return const LoginScreen();
      },
    );
  }
}

class RegistrationGate extends StatefulWidget {
  const RegistrationGate({super.key, required this.session});

  final UserSession session;

  @override
  State<RegistrationGate> createState() => _RegistrationGateState();
}

class _RegistrationGateState extends State<RegistrationGate> {
  final ApiService _api = ApiService();
  late Future<UserProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<UserProfile?> _loadProfile() async {
    await _api.updateAuthToken(widget.session.token);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Resetea OfflineSyncStatus al login para que no quede pegado en offline tras un 401 nocturno][obj: RegistrationGate._loadProfile resetOfflineStatus]
    final offlineStatus = GetIt.I<OfflineSyncStatus>();
    if (!offlineStatus.backendAvailable) {
      logInfo('OfflineSyncStatus: reseteando a disponible tras nuevo login');
      offlineStatus.setBackendAvailable(true);
    } else {
      logInfo('OfflineSyncStatus: ya estaba disponible, sin cambios');
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Al reingresar, flushea primero la cola local (incluye puntos nativos capturados sin sesión)][obj: RegistrationGate._loadProfile flushPending]
    try {
      final sync = LocationSyncManager(apiService: _api);
      await sync.flushPending(firebaseUid: widget.session.uid);
    } catch (e, st) {
      logError('Flush pending al login falló', error: e, stackTrace: st);
    }
    OfflineSyncBootstrap.start();
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: Pre-carga cuestionario activo al login para disponibilidad offline. El fetch en _handleCuestionarioAsignado actualiza este cache antes de cada visita.][obj: RegistrationGate._loadProfile prefetch questionnaire]
    unawaited(_prefetchQuestionnaireCache());
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Fuerza perfil desde red para evitar horario desactualizado en pantalla “fuera de horario”】【obj: RegistrationGate._loadProfile forceNetwork]
    UserProfile? profile;
    try {
      profile = await _api.fetchUserProfile(
        widget.session.uid,
        forceNetwork: true,
      );
    } catch (e, st) {
      if (ApiService.isSessionExpiredError(e)) {
        logWarn(
          'Sesión expirada durante carga de perfil; no se intentará fallback a caché',
          details: e.toString(),
        );
        rethrow;
      }
      logWarn(
        'No se pudo cargar perfil desde red; usando caché si existe',
        details: e.toString(),
      );
      logError(
        'fetchUserProfile(forceNetwork) falló',
        error: e,
        stackTrace: st,
      );
      profile = await _api.fetchUserProfile(widget.session.uid);
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Traza perfil/horarioId para depurar pantalla “fuera de horario” con horas incorrectas][obj: RegistrationGate._loadProfile profile trace]
    logDebug(
      'Perfil cargado',
      details:
          'uid=${widget.session.uid} horarioId=${profile?.horarioId} horarioNombre=${profile?.horarioNombre}',
    );
    if (profile != null && profile.horarioId != null) {
      try {
        final horario = await _api.fetchHorarioById(profile.horarioId!);
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Traza detalle de horario (horaInicio/horaFin) usado por el gate de horario][obj: RegistrationGate._loadProfile horario trace]
        logDebug(
          'Horario obtenido',
          details:
              'horarioId=${profile.horarioId} nombre=${horario.nombre} ${horario.horaInicio}-${horario.horaFin}',
        );
        await GetIt.I<IdentityService>().setHorario(
          inicio: horario.horaInicio,
          fin: horario.horaFin,
        );
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Persiste horario y programa AlarmManager exacto para tracking en background (Android)][obj: RegistrationGate._loadProfile]
        await BackgroundScheduleManager.upsertScheduleAndProgramAlarms(
          horarioId: profile.horarioId!,
          horaInicio: horario.horaInicio,
          horaFin: horario.horaFin,
          horarioNombre: horario.nombre,
        );
      } catch (_) {
        await GetIt.I<IdentityService>().clearHorario();
      }
    } else {
      await GetIt.I<IdentityService>().clearHorario();
    }
    return profile;
  }

  Future<void> _prefetchQuestionnaireCache() async {
    try {
      final cuestionario = await _api.fetchCuestionarioActivo();
      if (cuestionario != null) {
        final preguntas = await _api.fetchPreguntasPorCuestionario(
          cuestionario.id,
        );
        await QuestionnaireCacheStore().save(
          cuestionario: cuestionario,
          preguntas: preguntas,
        );
        logDebug(
          'Cuestionario pre-cargado al login',
          details: 'id=${cuestionario.id}',
        );
      }
    } catch (e) {
      logWarn(
        'No se pudo pre-cargar cuestionario al login',
        details: e.toString(),
      );
    }
  }

  bool _isOutsideSchedule() {
    final start = GetIt.I<IdentityService>().horarioInicio;
    final end = GetIt.I<IdentityService>().horarioFin;
    if (start == null || end == null) return false;
    final now = DateTime.now();
    final startDt = DateTime(now.year, now.month, now.day, start);
    final endDt = DateTime(now.year, now.month, now.day, end);
    return now.isBefore(startDt) || now.isAfter(endDt);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudo validar tu perfil.'),
                    const SizedBox(height: 12),
                    Text(snapshot.error.toString()),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _profileFuture = _loadProfile());
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final profile = snapshot.data;
        if (profile != null) {
          return const MapScreen();
        }
        return RegistrationInfoScreen(session: widget.session);
      },
    );
  }
}

class OutOfScheduleScreen extends StatelessWidget {
  const OutOfScheduleScreen({
    super.key,
    required this.session,
    required this.startHour,
    required this.endHour,
  });

  final UserSession session;
  final int? startHour;
  final int? endHour;

  String _windowLabel() {
    final s = startHour ?? 0;
    final e = endHour ?? 0;
    return '${s.toString().padLeft(2, '0')}:00 - ${e.toString().padLeft(2, '0')}:00';
  }

  Future<void> _logout(BuildContext context) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Fuerza flush de ubicaciones pendientes antes de cerrar sesión][obj: OutOfScheduleScreen._logout]
    await LogoutFlushService.flushPendingBeforeLogout(
      uid: session.uid,
      token: session.token,
    );
    try {
      await GetIt.I<AuthService>().signOutSaa();
    } catch (_) {
      await GetIt.I<AuthService>().signOut();
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Asegura fg_tracking_active=false antes de enforceNow en logout para permitir tracking nativo por horario][obj: OutOfScheduleScreen._logout fg_tracking_active]
    await BackgroundScheduleManager.setForegroundTrackingActive(false);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Tras logout real, fuerza enforceNow Android para continuar tracking por horario (si aplica)][obj: OutOfScheduleScreen._logout enforceNow]
    await BackgroundScheduleManager.enforceNow();
    await GetIt.I<IdentityService>().clearHorario();
    if (context.mounted) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Limpia ruta y estado de sesión del MapScreenController (singleton Provider) para que el siguiente usuario no vea el recorrido anterior][obj: OutOfScheduleScreen._logout resetForNewSession]
      context.read<MapScreenController>().resetForNewSession();
      Navigator.of(context).pushAndRemoveUntil(
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Regresa al AuthGate limpiando pila tras logout][obj: OutOfScheduleScreen._logout]
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock, size: 64),
                const SizedBox(height: 12),
                Text(
                  'Fuera de horario',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Puedes usar la app solo entre ${_windowLabel()}. Inténtalo más tarde.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _logout(context),
                  child: const Text('Salir'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegistrationInfoScreen extends StatelessWidget {
  const RegistrationInfoScreen({super.key, required this.session});

  final UserSession session;

  Future<void> _logout(BuildContext context) async {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Fuerza flush de ubicaciones pendientes antes de limpiar prefs/SQLite][obj: RegistrationInfoScreen._logout]
    await LogoutFlushService.flushPendingBeforeLogout(
      uid: session.uid,
      token: session.token,
    );
    try {
      await GetIt.I<AuthService>().signOutSaa();
    } catch (_) {
      await GetIt.I<AuthService>().signOut();
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Asegura fg_tracking_active=false antes de enforceNow en logout para permitir tracking nativo por horario][obj: RegistrationInfoScreen._logout fg_tracking_active]
    await BackgroundScheduleManager.setForegroundTrackingActive(false);
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Tras logout real, fuerza enforceNow Android para continuar tracking por horario (si aplica)][obj: RegistrationInfoScreen._logout enforceNow]
    await BackgroundScheduleManager.enforceNow();
    await GetIt.I<IdentityService>().clearHorario();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    try {
      await GetIt.I<DatabaseService>().clearDatabase();
    } catch (_) {}
    if (context.mounted) {
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Limpia ruta y estado de sesión del MapScreenController (singleton Provider) para que el siguiente usuario no vea el recorrido anterior][obj: RegistrationInfoScreen._logout resetForNewSession]
      context.read<MapScreenController>().resetForNewSession();
      Navigator.of(context).pushAndRemoveUntil(
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Logout completo hacia AuthGate desde pantalla informativa][obj: RegistrationInfoScreen._logout]
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 64),
                const SizedBox(height: 12),
                Text(
                  'El usuario no está registrado en el sistema',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _logout(context),
                  child: const Text('Salir'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
