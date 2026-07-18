import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barre supérieure commune, divisée en 4 quarts de gauche à droite :
/// 1) le logo MPG · 2-3) le nom de la page (centré) · 4) les actions
/// (armoire à badges, paramètres).
class GrintaAppBar extends AppBar {
  GrintaAppBar({
    required Widget title,
    super.key,
    List<Widget>? actions,
    super.bottom,
  }) : super(
          toolbarHeight: 104,
          titleSpacing: 0,
          centerTitle: false,
          title: _GrintaTitleBar(pageName: title, actions: actions),
        );
}

class _GrintaTitleBar extends StatelessWidget {
  const _GrintaTitleBar({required this.pageName, this.actions});

  final Widget pageName;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Logo MPG, aligné à gauche.
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              // Variante « barre » : le mot-symbole MPG est centré
              // verticalement (padding bas) pour tomber pile au niveau du
              // milieu du titre de la page, quelle que soit l'échelle.
              child: Image.asset(
                'assets/images/mpg_logo_bar.png',
                height: 96,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Nom de la page, centré. On réduit la taille si le titre est long
          // plutôt que de le tronquer.
          Expanded(
            flex: 3,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: DefaultTextStyle.merge(
                  textAlign: TextAlign.center,
                  softWrap: false,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                  child: pageName,
                ),
              ),
            ),
          ),
          // Actions (armoire, paramètres), alignées à droite.
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: actions ?? const [],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Actions communes du 4e quart des onglets principaux : l'armoire à badges
/// (à gauche) puis les paramètres (engrenage, à droite).
List<Widget> grintaHomeActions(BuildContext context) => [
      IconButton(
        tooltip: 'Armoire à badges',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        constraints: const BoxConstraints(),
        icon: const Text('🏆', style: TextStyle(fontSize: 28)),
        onPressed: () => context.push('/armoire'),
      ),
      const SizedBox(width: 6),
      IconButton(
        tooltip: 'Paramètres',
        iconSize: 30,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        constraints: const BoxConstraints(),
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => context.push('/more'),
      ),
    ];
