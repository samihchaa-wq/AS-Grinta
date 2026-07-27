import 'dart:async';
import 'dart:ui';

import 'package:as_grinta/app/app.dart';
import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/incident_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark(),
      home: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError) {
            return const ProviderScope(child: AsGrintaApp());
          }

          if (snapshot.hasError) {
            return IncidentErrorView(
              title: 'Impossible de démarrer Ma Petite Grinta',
              message: 'La configuration ou le service est momentanément '
                  'indisponible. Réessaie dans un instant.',
              incidentReference:
                  _incidentReference ?? AppLogger.createIncidentReference(),
              onRetry: _retry,
            );
          }

          return Scaffold(
            backgroundColor: const Color(0xFF07142E),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Image.asset(
                          'assets/images/mpg_logo.png',
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Ma Petite Grinta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const GrintaLoader.inline(
                        message: 'Échauffement en cours…',
                        semanticLabel: 'Démarrage de Ma Petite Grinta',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
