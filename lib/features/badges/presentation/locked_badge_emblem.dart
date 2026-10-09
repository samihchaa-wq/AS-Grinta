import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Désature un emblème (noir et blanc) : coefficients de luminance usuels.
const ColorFilter _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Emblème d'un badge que la personne n'a pas encore : en noir et blanc,
/// légèrement assombri, avec un cadenas posé au centre.
class LockedBadgeEmblem extends StatelessWidget {
  const LockedBadgeEmblem({
    super.key,
    required this.emblem,
    required this.size,
  });

  /// L'emblème normal du badge, tel qu'il s'afficherait une fois gagné.
  final Widget emblem;

  /// Largeur de l'emblème : sert à dimensionner le cadenas.
  final double size;

  @override
  Widget build(BuildContext context) {
    final lockSize = (size * .3).clamp(16.0, 40.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: .55,
          child: ColorFiltered(colorFilter: _grayscale, child: emblem),
        ),
        Container(
          padding: EdgeInsets.all(lockSize * .28),
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: .78),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.outline.withValues(alpha: .6)),
          ),
          child: Icon(
            Icons.lock_outline_rounded,
            size: lockSize,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
