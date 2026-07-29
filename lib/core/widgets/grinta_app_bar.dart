import 'dart:ui';

import 'package:as_grinta/core/theme/app_theme.dart';
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
}

class _HeaderBackdrop extends StatelessWidget {
  const _HeaderBackdrop();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.surface.withValues(alpha: .9),
                AppTheme.surface.withValues(alpha: .7),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: AppTheme.outline.withValues(alpha: .24),
              ),
            ),
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'assets/images/mpg_logo_bar.png',
                height: 38,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
              child: pageName,
            ),
          ),
          if (admin || (actions?.isNotEmpty ?? false)) ...[
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (admin) ...[
                    const AdminBadge(),
                    if (actions != null && actions!.isNotEmpty)
                      const SizedBox(width: 4),
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
        iconSize: 22,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(7),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        style: IconButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          backgroundColor: AppTheme.surfaceHigh.withValues(alpha: .46),
        ),
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => context.push('/more'),
      ),
    ];
