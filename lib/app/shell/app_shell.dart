import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({
    required this.child,
    required this.location,
    super.key,
  });

  final Widget child;
  final String location;

  bool get _isMoreRoute {
    const moreRoutes = {
      '/more',
      '/profile',
      '/notifications',
      '/faq',
      '/admin',
      '/players',
    };
    return moreRoutes.any(
      (route) => location == route || location.startsWith('$route/'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Align(
            alignment: Alignment.centerRight,
            heightFactor: 1,
            child: FractionallySizedBox(
              widthFactor: .34,
              child: Material(
                color: _isMoreRoute
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    if (location != '/more') context.go('/more');
                  },
                  child: const SizedBox(
                    height: 54,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings_rounded, size: 22),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Plus',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
