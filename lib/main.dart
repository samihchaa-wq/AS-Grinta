import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:as_grinta/app/app.dart';
import 'package:as_grinta/app/router/initial_app_location.dart';
import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/widgets/grinta_animated_crest.dart';
import 'package:as_grinta/core/widgets/grinta_background.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/incident_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Le MaterialApp de bootstrap peut normaliser le hash avant que GoRouter
    // ne soit créé. Capturer la destination demandée ici préserve un deep-link
    // ouvert à froid pendant toute l'initialisation Supabase.
    captureInitialAppLocation();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLogger.error('flutter.framework', details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      AppLogger.error('flutter.platform', error, stackTrace);
      return true;
    };
    ErrorWidget.builder = (details) {
      final reference = AppLogger.error(
        'flutter.render',
        details.exception,
        details.stack,
      );
      return IncidentErrorView(
        title: 'Une erreur est survenue',
        message:
            'Cette partie de l’application est momentanément indisponible.',
        incidentReference: reference,
      );
    };

    runApp(const _BootstrapApp());
  }, (error, stackTrace) => AppLogger.error('flutter.zone', error, stackTrace));
}

/// Rend les références d'incident réellement retrouvables.
///
/// La RPC ne reçoit que l'opération, le type d'erreur, la version et la
/// référence — jamais le message de l'erreur. L'envoi est délibérément
/// « au mieux » : un échec ne doit ni remonter à l'utilisateur, ni relancer le
/// gestionnaire d'erreurs global.
void _installIncidentSink() {
  AppLogger.sink = (incident) {
    unawaited(
      Supabase.instance.client.rpc(
        'log_client_incident',
        params: {
          'p_reference': incident.reference,
          'p_operation': incident.operation,
          'p_error_type': incident.errorType,
          'p_app_version': incident.appVersion,
        },
      ).catchError((Object _) => null),
    );
  };
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late Future<void> _initialization;
  String? _incidentReference;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    try {
      AppConfig.validate();
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      ).timeout(const Duration(seconds: 20));
      _installIncidentSink();
    } catch (error, stackTrace) {
      _incidentReference = AppLogger.error(
        'bootstrap.supabase',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _incidentReference = null;
      _initialization = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Le FutureBuilder est volontairement *au-dessus* de tout MaterialApp :
    // l'amorçage et l'application rendent chacun le leur, jamais l'un dans
    // l'autre. Deux MaterialApp imbriqués donnaient deux Navigator, et le
    // WidgetsApp externe levait une exception à chaque changement de hash
    // (Retour, Suivant, restauration PWA) en tombant sur `onUnknownRoute` nul.
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return const ProviderScope(child: AsGrintaApp());
        }
        return _BootstrapShell(
          home: snapshot.hasError
              ? IncidentErrorView(
                  title: 'Impossible de démarrer ASG',
                  message: 'La configuration ou le service est momentanément '
                      'indisponible. Réessaie dans un instant.',
                  incidentReference:
                      _incidentReference ?? AppLogger.createIncidentReference(),
                  onRetry: _retry,
                )
              : const _BootstrapSplash(),
        );
      },
    );
  }
}

/// Coquille minimale de l'amorçage : le seul MaterialApp affiché tant que
/// Supabase n'est pas initialisé.
class _BootstrapShell extends StatelessWidget {
  const _BootstrapShell({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      builder: (context, child) => GrintaBackground(
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    );
  }
}

class _BootstrapSplash extends StatelessWidget {
  const _BootstrapSplash();

  @override
  Widget build(BuildContext context) {
    // Sur les écrans très étroits, l'écusson doit rester dans la page une fois
    // les marges retirées.
    final crestWidth = math
        .min(240.0, MediaQuery.sizeOf(context).width - 64)
        .clamp(120.0, 240.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GrintaAnimatedCrest(width: crestWidth.toDouble()),
                const SizedBox(height: 28),
                const GrintaStartupProgressBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
