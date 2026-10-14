import 'dart:async';

import 'package:as_grinta/app/router/app_router.dart';
import 'package:as_grinta/core/network/connectivity_service.dart';
import 'package:as_grinta/core/push/push_client.dart';
import 'package:as_grinta/core/sync/shared_data_sync.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_accessibility_scope.dart';
import 'package:as_grinta/core/widgets/grinta_status_banner.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/notifications/data/notification_inbox_repository.dart';
import 'package:as_grinta/features/notifications/presentation/push_device_banner.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
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
    // Session restaurée au lancement ou nouvelle connexion : l'abonnement
    // aux notifications de cet appareil est recollé au compte connecté.
    ref.listenManual<bool>(
      authControllerProvider.select((state) => state.isAuthenticated),
      (previous, next) {
        if (next && previous != true) unawaited(_resyncPushSubscription());
      },
      fireImmediately: true,
    );
    // Notification reçue pendant que l'application est ouverte : la cloche
    // se met à jour sans attendre le prochain retour au premier plan.
    pushListenReceived(() {
      if (mounted) ref.invalidate(unreadNotificationCountProvider);
    });
    // L'icône de l'application porte le même chiffre que la cloche (zéro
    // hors connexion : la pastille du compte précédent disparaît).
    ref.listenManual<AsyncValue<int>>(
      unreadNotificationCountProvider,
      (_, next) {
        final count = next.valueOrNull;
        if (count != null) unawaited(pushSetAppBadge(count));
      },
      fireImmediately: true,
    );
  }

  /// La cloche des notifications reflète l'abonnement du navigateur, que le
  /// serveur peut avoir perdu (autre compte connecté sur ce téléphone, appareil
  /// remplacé…). Le réenregistrer à chaque ouverture évite qu'elle reste verte
  /// alors que plus rien n'arrive. Sans abonnement, rien n'est demandé.
  Future<void> _resyncPushSubscription() async {
    try {
      await ref.read(pushSubscriptionsRepositoryProvider).resync();
    } catch (_) {
      // Au mieux : l'échec ne change rien pour l'utilisateur, le prochain
      // lancement réessaiera.
    }
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
      // Une application installée sur iPhone reprend souvent sans relancer :
      // le retour au premier plan compte comme une ouverture.
      if (ref.read(authControllerProvider).isAuthenticated) {
        unawaited(_resyncPushSubscription());
      }
      // Le joueur revient peut-être des réglages du téléphone.
      ref.invalidate(pushStatusProvider);
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
    final isAuthenticated = ref.watch(
      authControllerProvider.select((state) => state.isAuthenticated),
    );
    final baseTheme = AppTheme.dark;

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
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: AppTheme.background,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        // Un état sélectionné se lit désormais avec le jaune club, sans
        // modifier le fond bleu déjà utilisé par les boutons/onglets actifs.
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: baseTheme.segmentedButtonTheme.style?.copyWith(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppTheme.accent;
              }
              return baseTheme.segmentedButtonTheme.style?.foregroundColor
                      ?.resolve(states) ??
                  AppTheme.textSecondary;
            }),
          ),
        ),
        navigationBarTheme: baseTheme.navigationBarTheme.copyWith(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            final inherited =
                baseTheme.navigationBarTheme.labelTextStyle?.resolve(states);
            return inherited?.copyWith(
                  color: selected ? AppTheme.accent : AppTheme.textFaint,
                ) ??
                TextStyle(
                  color: selected ? AppTheme.accent : AppTheme.textFaint,
                );
          }),
        ),
      ),
      routerConfig: router,
      builder: (context, child) {
        // Le réglage d'accessibilité du système / du navigateur doit être
        // respecté : un facteur fixe l'écrasait purement et simplement, et
        // « très grand texte » ne changeait pas un pixel (échec WCAG 1.4.4).
        // On garde le confort de lecture de base en plancher, et un plafond
        // pour ne pas casser les mises en page denses.
        final systemScale = MediaQuery.textScalerOf(context).scale(1);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              (systemScale * 1.10).clamp(1.10, 1.60),
            ),
          ),
          child: GrintaAccessibilityScope(
            child: ColoredBox(
              color: AppTheme.background,
              child: Column(
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
                  if (isAuthenticated) const PushDeviceBanner(),
                  Expanded(child: child ?? const SizedBox.shrink()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
