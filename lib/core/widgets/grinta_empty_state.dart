import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Message vide, informatif ou d'erreur cohérent dans toute l'application.
///
/// Le contenu reste volontairement court : une illustration symbolique, un
/// titre lisible immédiatement, une explication secondaire et, si nécessaire,
/// une seule action claire.
class GrintaEmptyState extends StatelessWidget {
  const GrintaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
    this.tone = GrintaEmptyTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;
  final GrintaEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = tone == GrintaEmptyTone.alert
        ? theme.colorScheme.error
        : AppTheme.primaryBright;
    final badge = compact ? 56.0 : 80.0;
    final iconSize = compact ? 28.0 : 38.0;

    final content = Semantics(
      container: true,
      label: [title, if (message case final value?) value].join('. '),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 24,
          vertical: compact ? 22 : 44,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: badge,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: .1),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(icon, size: iconSize, color: accent),
                  ),
                ),
                SizedBox(height: compact ? 14 : 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: (compact
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleLarge)
                      ?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (message case final value? when value.trim().isNotEmpty) ...[
                  SizedBox(height: compact ? 6 : 8),
                  Text(
                    value,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textFaint,
                      height: 1.45,
                    ),
                  ),
                ],
                if (action != null) ...[
                  SizedBox(height: compact ? 18 : 24),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: content,
    );
  }
}

enum GrintaEmptyTone { neutral, alert }
