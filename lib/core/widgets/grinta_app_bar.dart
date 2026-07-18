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
          // 1er quart : logo MPG, aligné à gauche.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'assets/images/mpg_logo.png',
                height: 72,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // 2e et 3e quarts : nom de la page, centré. On réduit la taille si le
          // titre est long plutôt que de le tronquer.
          Expanded(
            flex: 2,
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
          // 4e quart : actions (armoire, paramètres), alignées à droite.
          Expanded(
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
        icon: const Text('🏆', style: TextStyle(fontSize: 20)),
        onPressed: () => context.push('/armoire'),
      ),
      IconButton(
        tooltip: 'Paramètres',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => context.push('/more'),
      ),
    ];
