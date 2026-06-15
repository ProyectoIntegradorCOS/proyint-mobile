// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:15 UTC-5 (Lima)][desc: Corrige import de auth_gate.dart][obj: SplashScreen imports]
import 'dart:async';

// import 'package:firebase_auth/firebase_auth.dart'; // Comentado: ya no se usa directo
import 'package:flutter/material.dart';

import '../auth/auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();

    // Navega tras una breve animación
    Timer(const Duration(milliseconds: 1500), _goNext);
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-04 23:15 UTC-5 (Lima)][desc: Usa nombres descriptivos en builders y elimina const incorrecta][obj: SplashScreen._goNext]
  void _goNext() {
    if (!mounted) return;
    // Ir al AuthGate que escucha cambios de autenticación y navega
    // automáticamente a Login o Map.
    final next = AuthGate();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => next,
        transitionsBuilder: (context, anim, secondaryAnimation, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/onp_logo.png',
                  width: 128,
                  height: 128,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                Text(
                  'Thaqhiri',
                  style: theme.textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
