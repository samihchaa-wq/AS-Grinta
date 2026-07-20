import 'dart:async';

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran d'accueil : point d'atterrissage de l'app.
/// 1) Parier sur le prochain match · 2) Ton dernier prono ·
/// 3) Tes classements · 4) Badges récents.
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
            ..invalidate(leaderboardProvider)
            ..invalidate(myArmoireProvider);
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
            _LastPronoBlock(),
            SizedBox(height: 18),
            _MyRankingsBlock(),
            SizedBox(height: 18),
            _RecentBadgesBlock(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── En-têtes de bloc ───────────────────────────

class _BlockHeader extends StatelessWidget {
  const _BlockHeader(this.emoji, this.title, {this.onSeeAll, this.seeAllLabel});
  final String emoji;
  final String title;
  final VoidCallback? onSeeAll;
  final String? seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(seeAllLabel ?? 'Voir tout'),
            ),
        ],
      ),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();
  @override
  Widget build(BuildContext context) => const Card(
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
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

// ───────────────────── 1) Parier sur le prochain match ─────────────────────

class _NextMatchBlock extends ConsumerWidget {
  const _NextMatchBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeDashboardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BlockHeader('⚽', 'Prochain match'),
        async.when(
          loading: () => const _MiniLoader(),
          error: (_, __) => const _EmptyCard('Impossible de charger le match.'),
          data: (data) {
            final match = data.nextMatch;
            if (match == null) {
              return const _EmptyCard('Aucun match à venir pour le moment.');
            }
            return _NextMatchCard(
              match: match,
              meetings: data.recentMeetings,
              predicted: data.nextMatchPredicted,
              participants: data.predictionParticipantCount,
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
    required this.meetings,
    required this.predicted,
    required this.participants,
  });

  final HomeMatch match;
  final List<RecentMeeting> meetings;
  final bool predicted;
  final int participants;

  @override
  Widget build(BuildContext context) {
    final homeName = match.isHome ? 'AS Grinta' : match.opponent;
    final awayName = match.isHome ? match.opponent : 'AS Grinta';
    // Les pronos ferment 5 minutes avant le coup d'envoi (ou manuellement).
    final closeAt = match.kickoffAt?.subtract(const Duration(minutes: 5));
    final open = !match.predictionsClosed &&
        closeAt != null &&
        DateTime.now().isBefore(closeAt);

    return Card(
      color: const Color(0xFF25164F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF9B6CFF), width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          open ? '/matches/${match.id}/prediction' : '/matches/${match.id}',
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (match.isHome ? AppTheme.primary : AppTheme.accent)
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      match.isHome ? 'Domicile' : 'Extérieur',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
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
              if (closeAt != null && !match.predictionsClosed) ...[
                const SizedBox(height: 10),
                _PronoCountdown(closeAt: closeAt),
              ],
              MatchAvailabilitySelector(
                matchId: match.id,
                embeddedOnDark: true,
                topSpacing: 14,
              ),
              if (match.hasOdds) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _OddsChip(label: 'V', value: match.oddsWin),
                    const SizedBox(width: 8),
                    _OddsChip(label: 'N', value: match.oddsDraw),
                    const SizedBox(width: 8),
                    _OddsChip(label: 'D', value: match.oddsLoss),
                  ],
                ),
              ],
              if (meetings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '5 dernières confrontations',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFCAB5FF),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final m in meetings) ...[
                      _MeetingDot(meeting: m),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    predicted ? Icons.check_circle : Icons.sports_soccer,
                    size: 18,
                    color: predicted ? const Color(0xFF52D08A) : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      predicted
                          ? 'Pari enregistré'
                          : open
                              ? 'Tu n\'as pas encore parié'
                              : 'Pronostics fermés',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color:
                            predicted ? const Color(0xFF52D08A) : Colors.white,
                      ),
                    ),
                  ),
                  if (open)
                    FilledButton(
                      onPressed: () =>
                          context.push('/matches/${match.id}/prediction'),
                      child: Text(predicted ? 'Modifier' : 'Parier'),
                    ),
                ],
              ),
              if (participants > 0) ...[
                const SizedBox(height: 8),
                Text(
                  AppFormats.counted(participants, 'pronostiqueur') +
                      (participants > 1 ? ' ont parié' : ' a parié'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB6A9E0),
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compte à rebours jusqu'à la clôture des pronos (coup d'envoi − 5 min).
class _PronoCountdown extends StatefulWidget {
  const _PronoCountdown({required this.closeAt});
  final DateTime closeAt;

  @override
  State<_PronoCountdown> createState() => _PronoCountdownState();
}

class _PronoCountdownState extends State<_PronoCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.closeAt.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = widget.closeAt.difference(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}j ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}min';
    if (d.inMinutes >= 1) return '${d.inMinutes}min ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final closed = _remaining.isNegative || _remaining == Duration.zero;
    final soon = !closed && _remaining.inHours < 1;
    final color = closed
        ? const Color(0xFF9299A5)
        : (soon ? AppTheme.accent : const Color(0xFFCAB5FF));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            closed ? Icons.lock_outline : Icons.timer_outlined,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            closed
                ? 'Pronos fermés'
                : 'Clôture des pronos dans ${_format(_remaining)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OddsChip extends StatelessWidget {
  const _OddsChip({required this.label, required this.value});
  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF160B36),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3F2A73)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFFB6A9E0),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AppFormats.odds(value),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingDot extends StatelessWidget {
  const _MeetingDot({required this.meeting});
  final RecentMeeting meeting;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String letter;
    if (meeting.isWin) {
      color = const Color(0xFF2E9E63);
      letter = 'V';
    } else if (meeting.isDraw) {
      color = const Color(0xFF8A6D2F);
      letter = 'N';
    } else {
      color = const Color(0xFFB23B4E);
      letter = 'D';
    }
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ─────────────────────────── 2) Ton dernier prono ───────────────────────────

class _LastPronoBlock extends ConsumerWidget {
  const _LastPronoBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myLastPronoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BlockHeader('🎯', 'Ton dernier prono'),
        async.when(
          loading: () => const _MiniLoader(),
          error: (_, __) =>
              const _EmptyCard('Impossible de charger ton prono.'),
          data: (prono) {
            if (prono == null) {
              return const _EmptyCard(
                'Tu n\'as pas encore de prono sur un match terminé.',
              );
            }
            return _LastPronoCard(prono: prono);
          },
        ),
      ],
    );
  }
}

class _LastPronoCard extends StatelessWidget {
  const _LastPronoCard({required this.prono});
  final LastProno prono;

  @override
  Widget build(BuildContext context) {
    final Color accent;
    if (prono.isWin) {
      accent = const Color(0xFF2E9E63);
    } else if (prono.isDraw) {
      accent = const Color(0xFF8A6D2F);
    } else {
      accent = const Color(0xFFB23B4E);
    }
    final homeName = prono.isHome ? 'AS Grinta' : prono.opponent;
    final awayName = prono.isHome ? prono.opponent : 'AS Grinta';
    final homeReal = prono.isHome ? prono.grintaScore : prono.opponentScore;
    final awayReal = prono.isHome ? prono.opponentScore : prono.grintaScore;
    final homePred = prono.isHome ? prono.predGrinta : prono.predAdverse;
    final awayPred = prono.isHome ? prono.predAdverse : prono.predGrinta;

    return Card(
      color: accent.withValues(alpha: 0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: accent.withValues(alpha: 0.7), width: 1.4),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/${prono.matchId}'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$homeName  $homeReal – $awayReal  $awayName',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Ton pari : $homePred – $awayPred'
                '${prono.useX2 ? '  ·  ×2' : ''}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (prono.exact)
                    const _ResultTag('Score exact', Color(0xFF52D08A))
                  else if (prono.goodWinner)
                    const _ResultTag('Bon vainqueur', Color(0xFF6BA0FF))
                  else
                    const _ResultTag('Raté', Color(0xFF9299A5)),
                  const Spacer(),
                  Text(
                    AppFormats.counted((prono.points * 100).round(), 'point'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: accent == const Color(0xFF8A6D2F)
                              ? Colors.white
                              : accent,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultTag extends StatelessWidget {
  const _ResultTag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─────────────────────────── 3) Tes classements ───────────────────────────

class _MyRankingsBlock extends ConsumerWidget {
  const _MyRankingsBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leaderboardProvider);
    final uid = ref.watch(authControllerProvider).profile?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BlockHeader('🏅', 'Tes classements'),
        async.when(
          loading: () => const _MiniLoader(),
          error: (_, __) =>
              const _EmptyCard('Impossible de charger les classements.'),
          data: (entries) {
            if (uid == null || entries.isEmpty) {
              return const _EmptyCard('Pas encore de classement.');
            }
            final total = entries.length;
            final matchRank = _rankOf(entries, uid, (e) => e.matchPoints);
            final seasonRank = _rankOf(entries, uid, (e) => e.seasonPoints);
            final generalRank = _rankOf(entries, uid, (e) => e.totalPoints);
            if (matchRank == null) {
              return const _EmptyCard(
                'Tu n\'apparais pas encore au classement.',
              );
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    _RankRow(
                      label: 'Matchs',
                      rank: matchRank,
                      total: total,
                      onTap: () =>
                          context.go('/pronos?category=general&view=matches'),
                    ),
                    const Divider(height: 1),
                    _RankRow(
                      label: 'Prono joueurs',
                      rank: seasonRank!,
                      total: total,
                      onTap: () =>
                          context.go('/pronos?category=general&view=scorers'),
                    ),
                    const Divider(height: 1),
                    _RankRow(
                      label: 'Général',
                      rank: generalRank!,
                      total: total,
                      highlight: true,
                      onTap: () =>
                          context.go('/pronos?category=general&view=general'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  int? _rankOf(
    List<LeaderboardEntry> entries,
    String uid,
    double Function(LeaderboardEntry) value,
  ) {
    final sorted = [...entries]..sort((a, b) => value(b).compareTo(value(a)));
    final index = sorted.indexWhere((e) => e.profileId == uid);
    return index < 0 ? null : index + 1;
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.label,
    required this.rank,
    required this.total,
    this.onTap,
    this.highlight = false,
  });
  final String label;
  final int rank;
  final int total;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                  ),
            ),
            const Spacer(),
            Text(
              '$rank',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: highlight ? AppTheme.accent : AppTheme.primaryBright,
                  ),
            ),
            Text(
              ' / $total',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── 4) Badges récents ───────────────────────────

class _RecentBadgesBlock extends ConsumerWidget {
  const _RecentBadgesBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myArmoireProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockHeader(
          '🏆',
          'Badges récents',
          seeAllLabel: 'Armoire',
          onSeeAll: () => context.push('/armoire'),
        ),
        async.when(
          loading: () => const _MiniLoader(),
          error: (_, __) =>
              const _EmptyCard('Impossible de charger tes badges.'),
          data: (armoire) {
            final recent = armoire.recent.take(4).toList();
            if (recent.isEmpty) {
              return const _EmptyCard(
                'Aucun badge pour l\'instant. À toi de jouer !',
              );
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final b in recent) _BadgeChip(badge: b)],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge});
  final ArmoireBadge badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Column(
        children: [
          BadgeEmblem(
            emoji: badge.def.emoji,
            imageUrl: badge.def.imageUrl,
            color: badge.def.color,
            baremeLabel: baremeLabelFor(badge.def.metric, badge.def.threshold),
            showStar: badge.def.hasStar,
            starCount: badge.stars,
            starsMultiplyBareme: isCareerBadgeCategory(badge.def.category),
            size: 66,
          ),
          const SizedBox(height: 6),
          // Hauteur fixe de 2 lignes : les noms courts comme longs occupent
          // la même place, donc tous les emblèmes restent alignés.
          SizedBox(
            height: 30,
            child: Text(
              badge.def.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
