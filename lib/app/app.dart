import 'package:as_grinta/app/router/app_router.dart';
import 'package:as_grinta/core/network/connectivity_service.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsGrintaApp extends ConsumerWidget {
  const AsGrintaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final onlineAsync = ref.watch(onlineStatusProvider);
    final isOnline = onlineAsync.valueOrNull ?? true;

    return MaterialApp.router(
      title: 'Ma Petite Grinta',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) {
        return Column(
          children: [
            if (!isOnline)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_outlined),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Connexion perdue. Les données affichées peuvent être obsolètes.',
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref.invalidate(onlineStatusProvider),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}
