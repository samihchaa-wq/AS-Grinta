import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final isStaff = authState.profile?.role.isStaff == true;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0C1D40), AppTheme.background],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(homeDashboardProvider);
              ref.invalidate(seasonPredictionsProvider);
              ref.invalidate(seasonPredictionsLockedProvider);
              await Future.wait([
                ref.read(homeDashboardProvider.future),
                ref.read(predictionsControllerProvider.notifier).load(),
              ]);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: _Header(
                      isStaff: isStaff,
                      onAdmin: () => context.go('/admin'),
                      onProfile: () => context.go('/profile'),
                      onLogout: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      dashboardAsync.when(
                        // On garde les données affichées pendant un
                        // rafraîchissement (pas d'écran de chargement au retour
                        // sur l'accueil) ; discret spinner au tout premier
                        // chargement.
                        skipLoadingOnRefresh: true,
                        skipLoadingOnReload: true,
                        loading: () => const Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (error, _) => _ErrorCard(
                          message: error.toString(),
                          onRetry: () => ref.invalidate(homeDashboardProvider),
                        ),
                        data: (dashboard) {
                          final next = dashboard.nextMatch;
                          final last = dashboard.lastMatch;
                          return Column(
                            children: [
                              // Prochain match en haut.
                              if (next != null) ...[
                                _NextMatchHero(match: next),
                                if (isStaff &&
                                    !next.isAwaitingResult &&
                                    !next.predictionsClosed) ...[
                                  const SizedBox(height: 12),
                                  _CloseProsButton(matchId: next.id),
                                ],
                                if (!next.isAwaitingResult) ...[
                                  const SizedBox(height: 16),
                                  _RecentMeetingsCard(
                                    opponent: next.opponent,
                                    meetings: dashboard.recentMeetings,
                                  ),
                                ],
                                const SizedBox(height: 16),
                                _InlinePrediction(
                                  participantCount:
                                      dashboard.predictionParticipantCount,
                                ),
                              ] else
                                const _NoUpcomingCard(),
                              const SizedBox(height: 16),
                              const _SeasonPredictionsCard(),
                              // Dernier match joué tout en bas.
                              if (last != null) ...[
                                const SizedBox(height: 16),
                                _LastMatchCard(match: last),
                              ],
                            ],
                          );
                        },
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isStaff,
    required this.onAdmin,
    required this.onProfile,
    required this.onLogout,
  });

  final bool isStaff;
  final VoidCallback onAdmin;
  final VoidCallback onProfile;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          'assets/images/mpg_logo.png',
          height: 84,
          fit: BoxFit.contain,
        ),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (value) async {
            if (value == 'admin') onAdmin();
            if (value == 'profile') onProfile();
            if (value == 'logout') await onLogout();
          },
          itemBuilder: (_) => [
            if (isStaff)
              const PopupMenuItem(
                value: 'admin',
                child: Text('👑  Administration'),
              ),
            const PopupMenuItem(value: 'profile', child: Text('Profil')),
            const PopupMenuItem(value: 'logout', child: Text('Déconnexion')),
          ],
        ),
      ],
    );
  }
}

/// Bouton réservé à l'admin (👑) : fermer manuellement les pronostics du
/// prochain match, en plus de la fermeture automatique 5 min avant le coup
/// d'envoi.
class _CloseProsButton extends ConsumerWidget {
  const _CloseProsButton({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accent),
        onPressed: () async {
          final confirmed =
              await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Fermer le prono ?'),
                  content: const Text(
                    'Plus personne ne pourra pronostiquer sur ce match, '
                    'même avant l’heure limite. C’est définitif.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Fermer'),
                    ),
                  ],
                ),
              ) ??
              false;
          if (!confirmed) return;
          try {
            await ref
                .read(matchesRepositoryProvider)
                .closeMatchPredictions(matchId);
            ref.invalidate(homeDashboardProvider);
            await ref.read(predictionsControllerProvider.notifier).load();
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
            }
          }
        },
        icon: const Icon(Icons.lock_clock_outlined),
        label: const Text('👑  Fermer le prono manuellement'),
      ),
    );
  }
}

/// Carte « Prochain match » (en haut de l'accueil) : intitulé dans l'ordre
/// domicile/extérieur, heure, cotes, et note d'attente de résultat.
class _NextMatchHero extends StatelessWidget {
  const _NextMatchHero({required this.match});

  final HomeMatch match;

  @override
  Widget build(BuildContext context) {
    final badge = match.isAwaitingResult
        ? 'EN ATTENTE DU RÉSULTAT'
        : 'PROCHAIN MATCH';
    // L'ordre indique le lieu : AS Grinta en premier = domicile.
    final title = match.isHome
        ? 'AS GRINTA  vs  ${match.opponent}'
        : '${match.opponent}  vs  AS GRINTA';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B3B6B), Color(0xFF0B1D40)],
        ),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (match.kickoffAt != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  AppFormats.dateTime(match.kickoffAt!),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ],
          if (match.isAwaitingResult)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Le résultat sera publié dès que la feuille de match sera '
                'validée.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            )
          else if (match.hasOdds) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _OddsPill(label: '1', value: match.oddsWin!),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OddsPill(label: 'N', value: match.oddsDraw!),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OddsPill(label: '2', value: match.oddsLoss!),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Une cote sous forme de pastille : « 1 · 2,10 ».
class _OddsPill extends StatelessWidget {
  const _OddsPill({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppFormats.odds(value),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte « Dernier match joué » (en bas de l'accueil).
class _LastMatchCard extends StatelessWidget {
  const _LastMatchCard({required this.match});

  final HomeMatch match;

  @override
  Widget build(BuildContext context) {
    final g = match.grintaScore ?? 0;
    final o = match.opponentScore ?? 0;
    // L'ordre indique le lieu : AS Grinta en premier = domicile.
    final title = match.isHome
        ? 'AS Grinta $g – $o ${match.opponent}'
        : '${match.opponent} $o – $g AS Grinta';

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sports_soccer_rounded,
                color: AppTheme.primaryBright,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'DERNIER MATCH JOUÉ',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (match.kickoffAt != null) ...[
            const SizedBox(height: 4),
            Text(
              AppFormats.date(match.kickoffAt!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/matches/${match.id}'),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Voir les points et les pronostics'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Affiché quand aucun match n'est programmé.
class _NoUpcomingCard extends StatelessWidget {
  const _NoUpcomingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B3B6B), Color(0xFF0B1D40)],
        ),
        border: Border.all(color: AppTheme.outline),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROCHAIN MATCH',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun match programmé',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}

class _RecentMeetingsCard extends StatelessWidget {
  const _RecentMeetingsCard({required this.opponent, required this.meetings});

  final String opponent;
  final List<RecentMeeting> meetings;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: AppTheme.primaryBright),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '5 derniers face-à-face',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Contre $opponent',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (meetings.isEmpty)
            const Text('Aucun précédent résultat enregistré.')
          else
            ...meetings.map((meeting) {
              final result = meeting.isWin
                  ? 'V'
                  : meeting.isDraw
                  ? 'N'
                  : 'D';
              final resultColor = meeting.isWin
                  ? Colors.greenAccent
                  : meeting.isDraw
                  ? Colors.amberAccent
                  : Colors.redAccent;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: resultColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        result,
                        style: TextStyle(
                          color: resultColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(AppFormats.date(meeting.date))),
                    Text(
                      '${meeting.grintaScore} – ${meeting.opponentScore}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _InlinePrediction extends ConsumerStatefulWidget {
  const _InlinePrediction({required this.participantCount});

  final int participantCount;

  @override
  ConsumerState<_InlinePrediction> createState() => _InlinePredictionState();
}

class _InlinePredictionState extends ConsumerState<_InlinePrediction> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(predictionsControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(predictionsControllerProvider);
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.items.isEmpty) return const SizedBox.shrink();

    final item = state.items.first;
    final isSaving = state.savingMatchId == item.matchId;
    final controller = ref.read(predictionsControllerProvider.notifier);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppTheme.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ton pronostic',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      item.isClosed
                          ? 'Pronostics fermés'
                          : 'Modifiable jusqu’à 5 minutes avant le coup d’envoi',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  item.isClosed
                      ? 'Fermés'
                      : item.isFilled
                      ? 'Enregistré'
                      : 'À saisir',
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _OddsRow(item: item),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.group_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                '${widget.participantCount} participant${widget.participantCount > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ScoreCol(
                  label: 'AS Grinta',
                  value: item.scoreGrinta,
                  enabled: item.canEdit && !isSaving,
                  onMinus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: true,
                    delta: -1,
                  ),
                  onPlus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: true,
                    delta: 1,
                  ),
                ),
              ),
              Text('–', style: Theme.of(context).textTheme.headlineMedium),
              Expanded(
                child: _ScoreCol(
                  label: item.opponentName,
                  value: item.scoreOpponent,
                  enabled: item.canEdit && !isSaving,
                  onMinus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: false,
                    delta: -1,
                  ),
                  onPlus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: false,
                    delta: 1,
                  ),
                ),
              ),
            ],
          ),
          if (!item.isClosed) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: item.useX2
                    ? const Color(0xFF6A32C7).withValues(alpha: .22)
                    : Colors.white.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: item.useX2
                      ? const Color(0xFF9B6CFF)
                      : Colors.white.withValues(alpha: .10),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: item.useX2
                        ? const Color(0xFFC5A7FF)
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.useX2 ? '×2 activé' : 'Activer le ×2',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${item.x2Available} en réserve · consommé même si le pronostic est faux',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: item.useX2,
                    onChanged:
                        (!item.useX2 && item.x2Available <= 0) || isSaving
                        ? null
                        : (_) => controller.toggleX2(item.matchId),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !item.canEdit || isSaving
                    ? null
                    : () async {
                        await controller.save(item.matchId);
                        ref.invalidate(homeDashboardProvider);
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Enregistrer'),
              ),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _OddsRow extends StatelessWidget {
  const _OddsRow({required this.item});

  final dynamic item;

  String _format(double? value) => value == null
      ? '—'
      : value
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+\$'), '')
            .replaceFirst(RegExp(r'\.\$'), '')
            .replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OddTile(label: '1', value: _format(item.oddsWin)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OddTile(label: 'N', value: _format(item.oddsDraw)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OddTile(label: '2', value: _format(item.oddsLoss)),
        ),
      ],
    );
  }
}

class _OddTile extends StatelessWidget {
  const _OddTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ScoreCol extends StatelessWidget {
  const _ScoreCol({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: enabled && value > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            IconButton(
              onPressed: enabled ? onPlus : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ],
    );
  }
}

/// Résumé des pronostics de saison de l'utilisateur, visible sur l'accueil
/// tant que les paris de saison ne sont pas verrouillés. Après verrouillage,
/// il est masqué (les jauges collectives prennent le relais dans l'onglet
/// Pronos).
class _SeasonPredictionsCard extends ConsumerWidget {
  const _SeasonPredictionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked =
        ref.watch(seasonPredictionsLockedProvider).valueOrNull ?? true;
    if (locked) return const SizedBox.shrink();

    final mineAsync = ref.watch(seasonPredictionsProvider);
    final items = mineAsync.valueOrNull;
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    final filledCount = items.where((i) => i.isFilled).length;
    final allFilled = filledCount == items.length;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Mes pronostics de saison',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(allFilled ? 'Complet' : 'À compléter'),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              allFilled
                  ? 'Tes pronostics sont enregistrés. Tu peux encore les '
                        'modifier tant que je ne les ai pas clôturés.'
                  : '$filledCount / ${items.length} joueur${items.length > 1 ? 's' : ''} '
                        'renseigné${filledCount > 1 ? 's' : ''}.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ...items.map((item) {
              final isKeeper = item.category == 'clean_sheets';
              final unit = isKeeper ? 'clean sheets' : 'buts';
              final filledLabel = isKeeper
                  ? AppFormats.counted(
                      item.value,
                      'clean sheet',
                      'clean sheets',
                    )
                  : AppFormats.counted(item.value, 'but');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      item.isFilled ? filledLabel : '— $unit',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: item.isFilled
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go('/pronos'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  allFilled
                      ? 'Modifier mes pronostics'
                      : 'Compléter mes pronostics',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outline),
      ),
      child: child,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, size: 38),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
