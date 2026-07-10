import 'package:as_grinta/features/coach/presentation/coach_board_controller.dart';
import 'package:as_grinta/features/coach/presentation/coach_production_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoachPage extends ConsumerWidget {
  const CoachPage({super.key});

  static const _noMatchMessage = 'Aucun match à venir ou en cours.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachBoardControllerProvider);

    if (state.isLoading) {
      return const Scaffold(
        appBar: _CoachAppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error == _noMatchMessage || state.matchId == null) {
      return Scaffold(
        appBar: const _CoachAppBar(),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(coachBoardControllerProvider);
            await Future<void>.delayed(const Duration(milliseconds: 400));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
            children: const [_NoMatchState()],
          ),
        ),
      );
    }

    return const CoachProductionPage();
  }
}

class _CoachAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CoachAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Tableau du coach'));
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.event_available_outlined,
            size: 42,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Aucun match prévu',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'Le Tableau sera disponible dès qu’un match à venir ou en cours sera programmé.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          'Tire vers le bas pour actualiser.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
