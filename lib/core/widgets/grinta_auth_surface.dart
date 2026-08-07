import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class GrintaAuthSurface extends StatelessWidget {
  const GrintaAuthSurface({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.maxWidth = 460,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 720 ? 40.0 : 20.0;
            final vertical = constraints.maxHeight >= 760 ? 32.0 : 20.0;
            return Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  vertical,
                  horizontal,
                  vertical + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(
                        constraints.maxWidth >= 520 ? 30 : 22,
                      ),
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              header: true,
                              label: 'AS La Grinta',
                              child: Image.asset(
                                'assets/images/as_grinta_logo.webp',
                                height: 138,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            if (title case final value?) ...[
                              const SizedBox(height: 20),
                              Text(
                                value,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                            if (subtitle case final value?) ...[
                              const SizedBox(height: 8),
                              Text(
                                value,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.textFaint,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            child,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
