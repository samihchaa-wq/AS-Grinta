import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// État vide (ou message plein écran) soigné et cohérent dans toute l'app :
/// une icône dans une pastille douce, un titre, un message secondaire
/// optionnel, et une action optionnelle.
///
/// À utiliser partout où une liste ou une section n'a rien à afficher
/// (« pas encore de match », classement vide, aucun badge, etc.) plutôt
/// qu'un simple `Text('Aucun…')`.
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

  /// Version resserrée pour une carte ou une petite section (moins d'espace).
  final bool compact;

  /// Teinte de la pastille : neutre (rose de marque) ou alerte (erreur).
  final GrintaEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = tone == GrintaEmptyTone.alert
        ? AppTheme.accent
        : AppTheme.primaryBright;
    final badge = compact ? 56.0 : 76.0;
    final iconSize = compact ? 28.0 : 38.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: compact ? 22 : 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: badge,
            width: badge,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, size: iconSize, color: accent),
          ),
          SizedBox(height: compact ? 12 : 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          if (action != null) ...[
            SizedBox(height: compact ? 16 : 22),
            action!,
          ],
        ],
      ),
    );
  }
}

enum GrintaEmptyTone { neutral, alert }
