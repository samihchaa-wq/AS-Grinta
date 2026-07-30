import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Barre de sous-onglets uniforme utilisée dans le module Stats.
///
/// Centralise les dimensions, les espacements et la typographie afin que les
/// sous-familles de Prono, Joueur et Équipe restent parfaitement alignées.
class GrintaSecondaryTabs<T> extends StatelessWidget {
  const GrintaSecondaryTabs({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    super.key,
  });

  static const double height = 36;

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: AppTheme.outline.withValues(alpha: .24)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: SegmentedButton<T>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: segments,
            selected: selected,
            onSelectionChanged: onSelectionChanged,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(0, height)),
              maximumSize: const WidgetStatePropertyAll(
                Size(double.infinity, height),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? const Color(0xFF1E3A66)
                    : Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? AppTheme.primaryBright
                    : AppTheme.textFaint;
              }),
              overlayColor: WidgetStatePropertyAll(
                AppTheme.primary.withValues(alpha: .08),
              ),
              side: const WidgetStatePropertyAll(BorderSide.none),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm - 2),
                ),
              ),
              textStyle: const WidgetStatePropertyAll(
                TextStyle(
                  fontSize: 12.5,
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
    );
  }
}
