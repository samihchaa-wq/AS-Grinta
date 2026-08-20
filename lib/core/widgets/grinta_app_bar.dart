import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/app_typography.dart';
import 'package:as_grinta/core/widgets/admin_badge.dart';
import 'package:as_grinta/features/badges/presentation/badge_trophy_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barre supérieure commune de l'application.
class GrintaAppBar extends AppBar {
  GrintaAppBar({
    required Widget title,
    super.key,
    List<Widget>? actions,
    bool admin = false,
    super.bottom,
  }) : super(
          toolbarHeight: 60,
          titleSpacing: 0,
          centerTitle: false,
          flexibleSpace: const _HeaderBackdrop(),
          title: _GrintaTitleBar(
            pageName: title,
            actions: actions,
            admin: admin,
          ),
        );

  /// Style commun des actions de la barre : un carré de 34 px, dont la cible
  /// tactile reste portée à 48 px par Material.
  static ButtonStyle actionStyle(BuildContext context) => IconButton.styleFrom(
        foregroundColor: AppTheme.textSecondary,
        backgroundColor: AppTheme.surfaceHigh,
        fixedSize: const Size.square(34),
        minimumSize: const Size.square(34),
        maximumSize: const Size.square(34),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
          side: const BorderSide(color: AppTheme.outlineMarked),
        ),
      );
}

class _HeaderBackdrop extends StatelessWidget {
  const _HeaderBackdrop();

  @override
  Widget build(BuildContext context) {
    // Fond plat : plus rien ne passe derrière la barre, donc plus besoin de
    // flouter quoi que ce soit ni de détourer le titre.
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBar,
        border: Border(bottom: BorderSide(color: AppTheme.progressTrack)),
      ),
    );
  }
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.contentGap,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/as_grinta_logo.webp',
            height: 30,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: AppSpacing.contentGap),
          Expanded(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontFamily: AppTypography.ui,
                color: AppTheme.textPrimary,
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: -.2,
              ),
              child: pageName,
            ),
          ),
          if (admin || (actions?.isNotEmpty ?? false)) ...[
            const SizedBox(width: 6),
            IconButtonTheme(
              data:
                  IconButtonThemeData(style: GrintaAppBar.actionStyle(context)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (admin) ...[
                    const AdminBadge(),
                    if (actions != null && actions!.isNotEmpty)
                      const SizedBox(width: AppSpacing.microGap),
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
      const SizedBox(width: 2),
      IconButton(
        tooltip: 'Paramètres',
        iconSize: 19,
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => context.push('/more'),
      ),
    ];
