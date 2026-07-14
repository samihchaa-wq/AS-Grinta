import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';

class AdminAccessDeniedPage extends StatelessWidget {
  const AdminAccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: GrintaAppBar(title: const SizedBox.shrink()),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
          child: Column(
            children: [
              SizedBox(
                height: 430,
                width: double.infinity,
                child: Image.asset(
                  'assets/images/admin_access_denied.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 42,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Text(
                'Tu n’as pas les droits',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'pour accéder à cette page.',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 34),
              Text(
                'Seuls les administrateurs peuvent accéder à cette section.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
