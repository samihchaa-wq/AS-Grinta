import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/admin_badge.dart';
import 'package:as_grinta/features/badges/presentation/badge_trophy_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barre supérieure commune de l'application.
///
/// [admin] ajoute la pastille « Admin » à droite : à activer sur toute page
/// réservée à l'administrateur.
class GrintaAppBar extends AppBar {
  GrintaAppBar({
    required Widget title,
    super.key,
    List<Widget>? actions,
    bool admin = false,
    super.bottom,
  }) : super(
          toolbarHeight: 76,
          titleSpacing: 0,
          centerTitle: false,
          title: _GrintaTitleBar(
            pageName: title,
            actions: actions,
            admin: admin,
          ),
        );
}

class _GrintaTitleBar extends StatelessWidget {
  const _GrintaTitleBar({
    required this.pageName,
    this.actions,
    this.admin = false,
  });

  final Widget pageName;
  final List<Widget>? actions;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'assets/images/mpg_logo_bar.png',
                height: 62,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.4,
                  ),
              child: pageName,
            ),
          ),
          if (admin || (actions?.isNotEmpty ?? false)) ...[
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 48),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (admin) ...[
                    const AdminBadge(),
                    if (actions != null && actions!.isNotEmpty)
                      const SizedBox(width: 6),
                  ],
                  ...?actions,
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<Widget> grintaHomeActions(BuildContext context) => [
      const BadgeTrophyButton(),
      const SizedBox(width: 4),
      IconButton(
        tooltip: 'Paramètres',
        iconSize: 25,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
        style: IconButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          backgroundColor: AppTheme.surface.withValues(alpha: .56),
        ),
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => context.push('/more'),
      ),
    ];
