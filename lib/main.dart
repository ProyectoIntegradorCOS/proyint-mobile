import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'services/telemetry_log_service.dart';
// import 'package:firebase_auth/firebase_auth.dart'; // Comentado: se migra a SAA
// import 'package:firebase_core/firebase_core.dart'; // Comentado
import 'package:flutter/material.dart';
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Agrega localizations delegates para DateRangePicker y textos en español][obj: LocationTrackerApp localizations]
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'firebase_options.dart'; // Comentado mientras se prueba SAA
import 'screens/splash/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/background_tasks.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'locator.dart';
import 'services/secure_token_store.dart';
import 'utils/logger.dart';

import 'screens/map/controllers/map_screen_controller.dart';
import 'screens/map/controllers/visit_controller.dart';
import 'screens/map/controllers/tracking_controller.dart';
import 'screens/map/controllers/route_controller.dart';
import 'screens/map/map_view_model.dart';
import 'services/location_service.dart';
import 'services/location_sync_manager.dart';
import 'services/mapbox_service.dart';
import 'config/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupLocator();
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Loguea versión y build number al arranque para identificar APK en telemetría][obj: main.dart app version log]
  final packageInfo = await PackageInfo.fromPlatform();
  unawaited(
    GetIt.I<TelemetryLogService>().log(
      'App iniciada: v${packageInfo.version} build=${packageInfo.buildNumber}',
    ),
  );
  await dotenv.load(fileName: '.env');
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 17:26 UTC-5 (Lima)][desc: Loguea y valida configuración efectiva de backend/SAA al arranque para diagnosticar qué fuente ganó (.env vs dart-define)][obj: main.dart resolved config]
  Constants.logResolvedConfig();
  final configIssues = Constants.validateRequiredConfig();
  if (configIssues.isNotEmpty) {
    logWarn('Configuración incompleta detectada', details: configIssues.join(' | '));
  }
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:47 UTC-5 (Lima)][desc: Limita WorkManager a Android; en iOS no existe soporte de periodic tasks equivalente][obj: main.dart:WorkManager init guard]
  if (Platform.isAndroid) {
    try {
      await Workmanager().initialize(backgroundTaskDispatcher);
      await registerBackgroundTasks();
    } catch (e, stack) {
      logError('Error inicializando WorkManager', error: e, stackTrace: stack);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:55 UTC-5 (Lima)][desc: Activa listener del EventChannel nativo iOS al inicio para recibir puntos de LocationTracker.swift][obj: main.dart iOS native listener]
  if (Platform.isIOS) {
    try {
      await GetIt.I<LocationService>().startNativeListener();
      logDebug('Listener nativo iOS activado');
    } catch (e, stack) {
      logError('Error activando listener nativo iOS', error: e, stackTrace: stack);
    }
  }

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-19 UTC-5 (Lima)][desc: Limpia Keychain iOS en primera ejecución post-instalación (el Keychain persiste entre reinstalaciones a diferencia de SharedPreferences)][obj: main.dart clearOnFirstRun]
  await SecureTokenStore.clearOnFirstRun();

  try {
    // Firebase.initializeApp(...) // Comentado temporalmente: usando SAA
    await GetIt.I<AuthService>().restoreSession();
    logDebug('Sesión SAA restaurada (si existía)');
  } catch (e, stack) {
    logError('Error restaurando sesión SAA', error: e, stackTrace: stack);
  }

  runApp(
    MultiProvider(
      providers: [
        // Servicios Core
        Provider<AuthService>(create: (_) => GetIt.I<AuthService>()),
        
        // Controladores de UI (Estado intermedio extraído de MapScreen)
        ChangeNotifierProvider(create: (_) => MapScreenController()),
        ChangeNotifierProvider(create: (_) => VisitController()),
        ChangeNotifierProvider(create: (_) => TrackingController(
          locationService: GetIt.I<LocationService>(),
          syncManager: GetIt.I<LocationSyncManager>(),
        )),
        ChangeNotifierProvider(create: (_) => RouteController(
          mapboxService: GetIt.I<MapboxService>(),
        )),

        // ViewModel integrador de Pantalla
        ChangeNotifierProvider(
          create: (context) => MapViewModel(
            stateController: context.read<MapScreenController>(),
            visitController: context.read<VisitController>(),
            trackingController: context.read<TrackingController>(),
            routeController: context.read<RouteController>(),
          ),
        ),
      ],
      child: const LocationTrackerApp(),
    ),
  );
}

class LocationTrackerApp extends StatelessWidget {
  const LocationTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Location Tracker',
      debugShowCheckedModeBanner: false,
      // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 00:00 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: LocationTrackerApp supportedLocales]
      supportedLocales: const [
        Locale('es', 'PE'),
        Locale('es', 'ES'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
