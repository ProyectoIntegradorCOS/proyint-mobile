import 'dart:async' show unawaited;
import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../services/background_schedule_manager.dart';
import '../../services/pending_location_retention_service.dart';
import '../../services/pending_location_store.dart';
import '../../services/telemetry_log_service.dart';
import '../../utils/logger.dart';
import '../map/map_screen.dart';
import 'auth_gate.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usuarioController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegisterMode = false; // Comentado conceptualmente: SSO no registra
  bool _isLoading = false;
  String? _errorMessage;
  bool _showPassword = false;
  bool _rememberUser = false;

  final AuthService _authService = GetIt.I<AuthService>();

  @override
  void initState() {
    super.initState();
    _loadRememberedUser();
  }

  Future<void> _loadRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_user') ?? false;
    String? usuario;
    if (remember) {
      usuario = prefs.getString('remembered_usuario');
    }
    if (mounted) {
      setState(() {
        _rememberUser = remember;
        if (usuario != null && usuario.isNotEmpty) {
          _usuarioController.text = usuario;
        }
      });
    } else {
      _rememberUser = remember;
      if (usuario != null && usuario.isNotEmpty) {
        _usuarioController.text = usuario;
      }
    }
  }

  Future<void> _persistRememberPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_user', value);
    if (!value) {
      // Si el usuario desactiva "Recordar", limpiar email almacenado
      await prefs.remove('remembered_usuario');
    }
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final usuario = _usuarioController.text.trim();
    final password = _passwordController.text.trim();

    if (usuario.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Ingresa usuario y contraseña');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Autenticación SAA (codigoSistema en duro)
      logDebug('Iniciando sesión en SAA', details: usuario);
      await _authService.signInSaa(
        usuario: usuario,
        contrasena: password,
        rememberCredenciales: false,
      );

      final apiService = ApiService();
      final token = _authService.currentSession?.token;
      if (token != null && token.isNotEmpty) {
        await apiService.updateAuthToken(token);
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-23 12:01 UTC-5 (Lima)][desc: Registra métrica de login en app móvil][obj: LoginScreen._submit]
        await apiService.sendMetric(
          action: 'login_mobile',
          screen: 'login',
          status: 'success',
        );
      }

      // Persistir preferencia de recordar usuario
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_user', _rememberUser);
      if (_rememberUser) {
        await prefs.setString('remembered_usuario', usuario);
      } else {
        await prefs.remove('remembered_usuario');
      }
      await prefs.remove('remember_creds');
      await prefs.remove('remembered_password');

      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Al hacer login, flush inmediato del SQLite nativo y Flutter al backend][obj: LoginScreen._submit flush on login]
      unawaited(() async {
        try {
          // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-18 UTC-5 (Lima)][desc: Log de pendientes antes del flush para diagnóstico][obj: LoginScreen._submit pre-flush count]
          final nativePre = await BackgroundScheduleManager.getNativeSqliteCount();
          final flutterStore = PendingLocationStore();
          final flutterPre = await flutterStore.count();
          GetIt.I<TelemetryLogService>().log('Login: pre-flush nativo=$nativePre flutter=$flutterPre');
          final nativeResult = await BackgroundScheduleManager.flushNativePendingNow();
          final flutterPost = await flutterStore.count();
          GetIt.I<TelemetryLogService>().log('Login: post-flush nativo=$nativeResult flutter_restantes=$flutterPost');
        } catch (e) {
          logDebug('Login: flush nativo falló', details: e.toString());
        }
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Purga puntos huérfanos de otros usuarios con más de 30 días al hacer login][obj: LoginScreen._submit purgeOrphaned]
        try {
          await PendingLocationRetentionService().purgeOrphaned();
        } catch (_) {}
      }());

      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-11 10:50 UTC-5][desc: Navega al flujo principal tras login][obj: LoginScreen._submit]
      logDebug('Login SAA exitoso, navegando a AuthGate');
      if (mounted) {
        // Dejar que AuthGate escuche el stream y navegue
        // ignore: use_build_context_synchronously
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      }
    } on Exception catch (e) {
      logError('Error en autenticación', error: e);
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //appBar: AppBar(title: const Text('Iniciar sesión')),
      appBar: AppBar(title: const Text('')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/onp_logo.png',
                          width: 96,
                          height: 96,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Inicio de sesión en Thaqhiri',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usuarioController,
                      decoration: const InputDecoration(labelText: 'Usuario'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _showPassword,
                          onChanged: (v) {
                            setState(() => _showPassword = v ?? false);
                          },
                        ),
                        const Text('Ver contraseña'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _rememberUser,
                          onChanged: (v) {
                            final newVal = v ?? false;
                            setState(() => _rememberUser = newVal);
                            // Guardar inmediatamente la preferencia de recordar
                            // (se mantiene tras cerrar sesión)
                            // No esperamos el Future para no bloquear la UI.
                            // ignore: discarded_futures
                            _persistRememberPreference(newVal);
                          },
                        ),
                        const Text('Recordar usuario'),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isRegisterMode ? 'Registrarme' : 'Ingresar',
                              ),
                      ),
                    ),
                    // Registro deshabilitado: flujo SSO
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
