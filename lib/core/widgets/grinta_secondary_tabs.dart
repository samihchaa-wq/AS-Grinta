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

  static const double height = 44;

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: SegmentedButton<T>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: segments,
          selected: selected,
          onSelectionChanged: onSelectionChanged,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, height)),
            maximumSize: WidgetStatePropertyAll(
              Size(double.infinity, height),
            ),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 8),
            ),
            textStyle: WidgetStatePropertyAll(
              TextStyle(
                fontSize: 15,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}
