import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Barre de sous-onglets uniforme.
///
/// Centralise les dimensions, les espacements et la typographie afin que les
/// sous-familles restent parfaitement alignées d'un module à l'autre.
class GrintaSecondaryTabs<T> extends StatelessWidget {
  const GrintaSecondaryTabs({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.secondLevel = false,
    super.key,
  });

  /// Hauteur de la barre. Elle ne descend pas sous 44 px : c'est la cible
  /// tactile minimale de l'application.
  static const double height = 44;

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  /// Sous-famille d'une sous-famille (« Actuelle / Précédente / Toutes ») :
  /// même principe, un cran plus discret.
  final bool secondLevel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        2,
        AppSpacing.screenGutter,
        AppSpacing.contentGap,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
          border: Border.all(color: AppTheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: SizedBox(
            width: double.infinity,
            height: height - 6,
            child: SegmentedButton<T>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: segments,
              selected: selected,
              onSelectionChanged: onSelectionChanged,
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(0, height - 6)),
                maximumSize: const WidgetStatePropertyAll(
                  Size(double.infinity, height - 6),
                ),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: AppSpacing.contentGap),
                ),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? AppTheme.surfaceHero
                      : Colors.transparent;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? Colors.white
                      : AppTheme.textLabel;
                }),
                overlayColor: WidgetStatePropertyAll(
                  AppTheme.primary.withValues(alpha: .08),
                ),
                side: const WidgetStatePropertyAll(BorderSide.none),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                textStyle: WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: AppTypography.ui,
                    fontSize: secondLevel ? 11.5 : 12.5,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .05,
                  ),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
