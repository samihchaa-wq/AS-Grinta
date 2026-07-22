import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/home/presentation/home_last_match_card.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AccueilPage extends ConsumerWidget {
  const AccueilPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Accueil'),
        actions: grintaHomeActions(context),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(homeDashboardProvider)
            ..invalidate(myLastPronoProvider)
            ..invalidate(sportMotmVoteProvider);
          await Future.wait([
            ref.read(homeDashboardProvider.future),
            ref.read(myLastPronoProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: const [
            _NextMatchBlock(),
            SizedBox(height: 18),
            HomeLastMatchCard(),
          ],
        ),
      ),
    );
  }
}

class _BlockHeader extends StatelessWidget {
  const _BlockHeader(this.icon, this.title);

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

class _NextMatchBlock extends ConsumerWidget {
  const _NextMatchBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeDashboardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BlockHeader(Icons.event_rounded, 'Prochain match'),
        async.when(
          loading: () => const _MiniLoader(),
          error: (_, __) => const _EmptyCard('Impossible de charger le match.'),
          data: (data) {
            final match = data.nextMatch;
            if (match == null) {
              return const _EmptyCard('Aucun match à venir pour le moment.');
            }
            final isAdmin = ref.watch(authControllerProvider).profile?.role ==
                AuthRole.admin;
            return _NextMatchCard(
              match: match,
              predicted: data.nextMatchPredicted,
              prediction: data.nextMatchPrediction,
              isAdmin: isAdmin,
            );
          },
        ),
      ],
    );
  }
}

class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({
    required this.match,
    required this.predicted,
    required this.prediction,
    required this.isAdmin,
  });

  final HomeMatch match;
  final bool predicted;
  final HomePrediction? prediction;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final homeName = match.isHome ? 'AS Grinta' : match.opponent;
    final awayName = match.isHome ? match.opponent : 'AS Grinta';
    final closeAt = match.kickoffAt?.subtract(const Duration(minutes: 5));
    final open = !match.predictionsClosed &&
        closeAt != null &&
        DateTime.now().isBefore(closeAt);
    final predictionScore = prediction == null
        ? null
        : match.isHome
            ? '${prediction!.grintaScore} – ${prediction!.opponentScore}'
            : '${prediction!.opponentScore} – ${prediction!.grintaScore}';

    return Card(
      color: const Color(0xFF25164F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF9B6CFF), width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          '/matches/${match.id}/lineup?section=effectif',
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$homeName  vs  $awayName',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFFD7C8FF)),
                ],
              ),
              if (match.kickoffAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  AppFormats.dateTime(match.kickoffAt!),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD7C8FF),
                      ),
                ),
              ],
              MatchAvailabilitySelector(
                matchId: match.id,
                embeddedOnDark: true,
                topSpacing: 14,
                showManageShortcut: isAdmin,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF160B36),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF3F2A73)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.sports_score_outlined, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Ton prono',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          predicted ? Icons.check_circle : Icons.edit_note,
                          size: 18,
                          color: predicted
                              ? const Color(0xFF52D08A)
                              : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            predicted && predictionScore != null
                                ? '$predictionScore'
                                    '${prediction!.useX2 ? ' · ×2' : ''}'
                                : open
                                    ? 'Pas encore rempli'
                                    : 'Pronostics fermés',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: predicted
                                  ? const Color(0xFF52D08A)
                                  : Colors.white,
                            ),
                          ),
                        ),
                        if (open)
                          FilledButton(
                            onPressed: () => context.push(
                              '/matches/${match.id}/lineup?section=prediction',
                            ),
                            child: Text(predicted ? 'Modifier' : 'Remplir'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
