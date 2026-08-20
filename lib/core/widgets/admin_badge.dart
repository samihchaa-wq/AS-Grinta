import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Pastille « Admin » affichée sur toutes les surfaces réservées à
/// l'administrateur, pour signaler clairement une zone de gestion.
///
/// Elle est volontairement discrète : c'est un repère de contexte, pas une
/// alerte, et le jaune du club est réservé à ce qui se passe en direct.
class AdminBadge extends StatelessWidget {
  const AdminBadge({super.key, this.label = 'Admin'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryBright.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(color: AppTheme.primary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 12,
            color: AppTheme.primaryBright,
          ),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: AppTypography.label(
              color: AppTheme.primaryBright,
              fontSize: 9.5,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
