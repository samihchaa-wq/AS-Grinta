import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Pastille « Admin » (bouclier rose) affichée sur toutes les surfaces
/// réservées à l'administrateur, pour signaler clairement une zone de gestion.
class AdminBadge extends StatelessWidget {
  const AdminBadge({super.key, this.label = 'Admin'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accent.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: AppTheme.accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
