import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_tab.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/presentation/upcoming_match_prediction_page.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_info_tab.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/inline_match_prediction_card.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_squad_plan_page.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/internal_team_composition_view.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_board_card.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MatchLineupPage extends ConsumerWidget {
  const MatchLineupPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queryParameters = GoRouterState.of(context).uri.queryParameters;
    if (queryParameters['infoOnly'] == 'true') {
      return _MatchInfoOnlyPage(matchId: matchId);
    }

    // Sans le module de gestion sportive, il n'y a ni effectif ni compo : on
    // ne prive pas le joueur de son prono pour autant. La fenêtre de saisie
    // reste protégée côté Supabase, y compris à T-15.
    if (!ref.watch(sportsManagementEnabledProvider)) {
      return UpcomingMatchPredictionPage(matchId: matchId);
    }

    final requestedSection = queryParameters['section'];
    final section = switch (requestedSection) {
      'info' => 'info',
      'composition' => 'composition',
      'live' => 'live',
      'prediction' => 'prediction',
      _ => 'effectif',
    };
    final isAdmin = ref.watch(isAdminViewProvider);
    final matchInfo = ref.watch(matchInfoProvider(matchId)).valueOrNull;
    final isInternal = matchInfo?.isInternal ?? false;

    // Une seule frontière temporelle : à T-15 le prono disparaît au moment
    // exact où le Live devient disponible.
    final tooFarAway = isMatchTooFarAway(matchInfo?.kickoffAt);
    final liveTooEarly = isMatchLiveTooEarly(matchInfo?.kickoffAt);
    final predictionClosed = isMatchPredictionClosed(matchInfo?.kickoffAt);

    if (isAdmin) {
      final adminSection = section == 'prediction' && predictionClosed
          ? (!isInternal && !liveTooEarly ? 'live' : 'effectif')
          : section == 'live' && (isInternal || liveTooEarly)
              ? 'effectif'
              : section;
      return AdminSquadPlanPage(
        initialMatchId: matchId,
        initialStep: adminSection,
        showPredictionStep: !isInternal && !predictionClosed,
      );
    }

    // Avant J-6 à midi, seul l'onglet Info est disponible. À partir de T-15,
    // une URL directe vers Prono est redirigée vers Live plutôt que d'afficher
    // un module désormais fermé.
    final resolvedSection = tooFarAway
        ? 'info'
        : section == 'live' && (isInternal || liveTooEarly)
            ? 'effectif'
            : section == 'prediction' && (isInternal || predictionClosed)
                ? (!isInternal && !liveTooEarly ? 'live' : 'effectif')
                : section;

    final showInfo = resolvedSection == 'info';
    final showEffectif = resolvedSection == 'effectif';
    final showComposition = resolvedSection == 'composition';
    final showLive = resolvedSection == 'live';
    final showPrediction = resolvedSection == 'prediction';

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Fiche du match')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(upcomingMatchFixtureProvider(matchId))
            ..invalidate(publishedMatchCompositionProvider(matchId))
            ..invalidate(matchAvailabilityBoardProvider(matchId))
            ..invalidate(matchInfoProvider(matchId))
            ..invalidate(inlineMatchPredictionProvider(matchId));
          await Future.wait([
            ref.read(upcomingMatchFixtureProvider(matchId).future),
            if (showComposition)
              ref.read(publishedMatchCompositionProvider(matchId).future),
            if (showEffectif)
              ref.read(matchAvailabilityBoardProvider(matchId).future),
            if (showInfo) ref.read(matchInfoProvider(matchId).future),
            if (showPrediction)
              ref.read(inlineMatchPredictionProvider(matchId).future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sectionGap,
            AppSpacing.screenGutter,
            40,
          ),
          children: [
            UpcomingMatchFixtureHeader(matchId: matchId),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: 'info', label: Text('Info')),
                if (!tooFarAway)
                  const ButtonSegment(
                    value: 'effectif',
                    label: Text('Effectif'),
                  ),
                if (!tooFarAway)
                  const ButtonSegment(
                    value: 'composition',
                    label: Text('Compo'),
                  ),
                if (!isInternal && !tooFarAway && !liveTooEarly)
                  const ButtonSegment(value: 'live', label: Text('Live')),
                if (!isInternal && !tooFarAway && !predictionClosed)
                  const ButtonSegment(
                    value: 'prediction',
                    label: Text('Prono'),
                  ),
              ],
              selected: {resolvedSection},
              onSelectionChanged: (selection) => context.go(
                '/matches/$matchId/lineup?section=${selection.first}',
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            if (showInfo) MatchInfoTab(matchId: matchId),
            if (showEffectif)
              MatchAvailabilityBoardCard(
                matchId: matchId,
                showAfterComposition: true,
              ),
            if (showComposition && isInternal)
              InternalTeamCompositionView(matchId: matchId, editable: false)
            else if (showComposition)
              PublishedLineupPreview(
                matchId: matchId,
                expanded: true,
                fallbackToEffectif: false,
                emptyMessage: 'Composition non publiée.',
              ),
            if (showLive) MatchLiveTab(matchId: matchId),
            if (showPrediction) InlineMatchPredictionCard(matchId: matchId),
          ],
        ),
      ),
    );
  }
}

class _MatchInfoOnlyPage extends ConsumerWidget {
  const _MatchInfoOnlyPage({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Fiche du match')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(matchInfoProvider(matchId));
          await ref.read(matchInfoProvider(matchId).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sectionGap,
            AppSpacing.screenGutter,
            40,
          ),
          children: [MatchInfoTab(matchId: matchId)],
        ),
      ),
    );
  }
}

class PublishedLineupCard extends ConsumerWidget {
  const PublishedLineupCard({
    super.key,
    required this.matchId,
    this.bottomSpacing = 0,
    this.showAvailabilityFlow = true,
  });

  final String matchId;
  final double bottomSpacing;
  final bool showAvailabilityFlow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(sportsManagementEnabledProvider)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showAvailabilityFlow)
              MatchAvailabilitySelector(
                matchId: matchId,
                bottomSpacing: AppSpacing.sectionGap,
              ),
            PublishedLineupPreview(matchId: matchId, showLists: true),
          ],
        ),
      ),
    );
  }
}

class PublishedLineupPreview extends ConsumerWidget {
  const PublishedLineupPreview({
    super.key,
    required this.matchId,
    this.embeddedOnDark = false,
    this.topSpacing = 0,
    this.bottomSpacing = 0,
    this.showLists = false,
    this.expanded = false,
    this.fallbackToEffectif = true,
    this.emptyMessage,
  });

  final String matchId;
  final bool embeddedOnDark;
  final double topSpacing;
  final double bottomSpacing;
  final bool showLists;
  final bool expanded;
  final bool fallbackToEffectif;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineup = ref.watch(publishedMatchCompositionProvider(matchId));
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: bottomSpacing),
      child: lineup.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const _MatchModuleError(
          message: 'Composition momentanément indisponible.',
        ),
        data: (composition) {
          if (composition == null) {
            if (fallbackToEffectif) {
              return MatchAvailabilityBoardCard(
                matchId: matchId,
                compact: true,
              );
            }
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Text(emptyMessage ?? 'Composition non publiée.'),
              ),
            );
          }
          final board =
              ref.watch(matchAvailabilityBoardProvider(matchId)).valueOrNull;
          final beforeKickoff =
              board == null || DateTime.now().isBefore(board.kickoffAt);
          final foreground = embeddedOnDark ? Colors.white : null;
          final secondary = embeddedOnDark ? Colors.white : null;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.groups_2_outlined, color: foreground),
                  const SizedBox(width: AppSpacing.contentGap),
                  Expanded(
                    child: Text(
                      'Composition',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  if (composition.formationCode != null)
                    Text(
                      composition.formationCode!,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.microGap),
              Text(
                'Composition publiée',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppSpacing.sectionGap),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: expanded ? 500 : 360),
                  child: CompositionPitch(
                    entries: composition.entriesFor(MatchCompositionZone.field),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sectionGap),
              Text(
                'Remplaçants (${composition.benchCount})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppSpacing.contentGap),
              if (composition.benchCount == 0)
                Text(
                  'Aucun remplaçant.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: secondary),
                )
              else
                Wrap(
                  spacing: AppSpacing.contentGap,
                  runSpacing: AppSpacing.contentGap,
                  children: [
                    for (final entry in composition.entriesFor(
                      MatchCompositionZone.bench,
                    ))
                      CompositionPlayerTile(entry: entry),
                  ],
                ),
              if (showLists && beforeKickoff) ...[
                const SizedBox(height: AppSpacing.sectionGap),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(
                    top: AppSpacing.contentGap,
                  ),
                  leading: Icon(Icons.list_alt_outlined, color: foreground),
                  title: Text(
                    'Voir les listes',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  children: [
                    MatchAvailabilityBoardCard(
                      matchId: matchId,
                      compact: true,
                      showAfterComposition: true,
                    ),
                  ],
                ),
              ],
            ],
          );
          if (embeddedOnDark) {
            return Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF9B6CFF).withValues(alpha: .55),
                ),
              ),
              child: content,
            );
          }
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: content,
            ),
          );
        },
      ),
    );
  }
}

class _MatchModuleError extends StatelessWidget {
  const _MatchModuleError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: AppSpacing.contentGap),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
