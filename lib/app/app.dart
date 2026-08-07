import 'dart:async';

import 'package:as_grinta/app/router/app_router.dart';
import 'package:as_grinta/core/network/connectivity_service.dart';
import 'package:as_grinta/core/sync/shared_data_sync.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_accessibility_scope.dart';
import 'package:as_grinta/core/widgets/grinta_app_background.dart';
import 'package:as_grinta/core/widgets/grinta_status_banner.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsGrintaApp extends ConsumerStatefulWidget {
  const AsGrintaApp({super.key});

  @override
  ConsumerState<AsGrintaApp> createState() => _AsGrintaAppState();
}

class _AsGrintaAppState extends ConsumerState<AsGrintaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(featureFlagsControllerProvider);
      // Reconnecte le signal Realtime et fait aussi un refresh explicite : un
      // iPhone peut suspendre le websocket pendant que l'application est en
      // arrière-plan, il ne faut donc pas dépendre d'un événement manqué.
      ref.invalidate(sharedDataSignalProvider);
      unawaited(ref.read(sharedDataRefreshCoordinatorProvider).refreshAll());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Maintient l'abonnement global tant que l'application est montée.
    ref.watch(sharedDataSyncListenerProvider);

    ref.listen<bool>(
      authControllerProvider.select((state) => state.isAuthenticated),
      (previous, next) {
        if (previous != next) {
          ref.invalidate(featureFlagsControllerProvider);
        }
      },
    );

    final router = ref.watch(appRouterProvider);
    final onlineAsync = ref.watch(onlineStatusProvider);
    final isOnline = onlineAsync.valueOrNull ?? true;

    return MaterialApp.router(
      title: 'ASG',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.dark.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      ),
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.10),
          ),
          child: GrintaAccessibilityScope(
            child: Stack(
              children: [
                const Positioned.fill(child: GrintaAppBackground()),
                Column(
                  children: [
                    if (!isOnline)
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: GrintaStatusBanner(
                              title: 'Connexion perdue',
                              message:
                                  'Les données affichées peuvent être obsolètes.',
                              tone: GrintaStatusTone.warning,
                              compact: true,
                              action: TextButton(
                                onPressed: () =>
                                    ref.invalidate(onlineStatusProvider),
                                child: const Text('Réessayer'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(child: child ?? const SizedBox.shrink()),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
