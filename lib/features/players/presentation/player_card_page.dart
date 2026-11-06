import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_secondary_tabs.dart';
import 'package:as_grinta/core/widgets/match_contribution_icons.dart';
import 'package:as_grinta/core/widgets/grinta_skeleton.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_detail_sheet.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/players/data/player_card_repository.dart';
import 'package:as_grinta/features/players/data/player_stat_ranking.dart';
import 'package:as_grinta/features/players/presentation/hero_photo_margin.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/stats_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'player_card_stats.dart';
part 'player_card_matches.dart';

const _display = 'Oswald';

/// Fiche joueur, ouverte en touchant un nom dans le module Statistiques.
///
/// Les chiffres par période viennent des mêmes classements que l'onglet
/// Joueurs (déjà en cache) ; seuls l'identité et les derniers matchs sont
/// chargés en plus.
class PlayerCardPage extends ConsumerStatefulWidget {
  const PlayerCardPage({super.key, required this.playerKey});

  final PlayerCardKey? playerKey;

  @override
  ConsumerState<PlayerCardPage> createState() => _PlayerCardPageState();
}

class _PlayerCardPageState extends ConsumerState<PlayerCardPage> {
  StatisticsPeriod _period = StatisticsPeriod.current;

  /// Une fois l'onglet Carrière ouvert, l'évolution reste chargée tant que la
  /// fiche est ouverte : y revenir ne la recharge pas et ne fait pas sauter
  /// la page.
  bool _careerOpened = false;

  /// Statistique choisie sur le graphique d'évolution ; `null` tant que
  /// l'utilisateur n'en a pas choisi.
  PlayerStat? _evolutionStat;

  Future<void> _refresh(PlayerCardKey key) async {
    for (final period in StatisticsPeriod.values) {
      ref.invalidate(statisticsPeriodProvider(period));
    }
    ref.invalidate(playerCardDetailsProvider(key));
    ref.invalidate(playerSeasonStatsProvider(key));
    ref.invalidate(playerCardBadgesProvider);
    await ref.read(playerCardDetailsProvider(key).future);
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.playerKey;
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Fiche joueur')),
      body: key == null
          ? const _Message(
              title: 'Joueur introuvable',
              message: 'Ce lien ne désigne aucun joueur.',
            )
          : _body(context, key),
    );
  }

  Widget _body(BuildContext context, PlayerCardKey key) {
    final details = ref.watch(playerCardDetailsProvider(key));
    final periodData = ref.watch(statisticsPeriodProvider(_period));
    final allTime =
        ref.watch(statisticsPeriodProvider(StatisticsPeriod.allTime));
    final seasons =
        _careerOpened ? ref.watch(playerSeasonStatsProvider(key)) : null;
    // Sert au seuil de classement de la saison en cours : il ne s'applique
    // qu'une fois passés les premiers matchs de l'équipe.
    final teamMatches = _period == StatisticsPeriod.current
        ? ref
            .watch(teamStatisticsPeriodProvider(StatisticsPeriod.current))
            .asData
            ?.value
            .matchesPlayed
        : null;

    if (details.isLoading && !details.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: GrintaSkeleton.rows(itemCount: 6),
      );
    }
    if (details.hasError && !details.hasValue) {
      return _Message(
        title: 'Fiche indisponible',
        message: humanizeError(details.error!),
      );
    }

    final info = details.requireValue;
    final careerRow = allTime.asData?.value.players
        .where((p) => isPlayerOfCard(p, key))
        .firstOrNull;
    if (info.firstName == null && careerRow == null && allTime.hasValue) {
      return const _Message(
        title: 'Pas de fiche joueur',
        message: 'Ce membre n’a encore joué aucun match avec l’équipe.',
      );
    }

    final name = info.firstName ??
        careerRow?.playerName ??
        capitalizePersonName(key.fullName);
    final isGoalkeeper = careerRow?.isGoalkeeper ?? key.isGoalkeeper;

    return RefreshIndicator(
      onRefresh: () => _refresh(key),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter + 4,
          12,
          AppSpacing.screenGutter + 4,
          32,
        ),
        children: [
          _Hero(
            name: name,
            nickname: info.nickname,
            photoUrl: info.photoUrl,
            profileId: info.profileId,
            isGoalkeeper: isGoalkeeper,
          ),
          const SizedBox(height: 16),
          GrintaSecondaryTabs<StatisticsPeriod>(
            segments: const [
              ButtonSegment(
                value: StatisticsPeriod.current,
                label: Text('Saison'),
              ),
              ButtonSegment(
                value: StatisticsPeriod.previous,
                label: Text('Précédente'),
              ),
              ButtonSegment(
                value: StatisticsPeriod.allTime,
                label: Text('Carrière'),
              ),
            ],
            selected: {_period},
            onSelectionChanged: (value) => setState(() {
              _period = value.first;
              if (_period == StatisticsPeriod.allTime) _careerOpened = true;
            }),
          ),
          const SizedBox(height: 12),
          periodData.when(
            loading: () => GrintaSkeleton.rows(itemCount: 2),
            error: (error, _) => _InlineNote(humanizeError(error)),
            data: (data) {
              final row =
                  data.players.where((p) => isPlayerOfCard(p, key)).firstOrNull;
              if (row == null) {
                return const _InlineNote('Aucun match sur cette période.');
              }
              return Column(
                children: [
                  _StatGrid(
                    playerKey: key,
                    player: row,
                    data: data,
                    teamMatches: teamMatches,
                  ),
                  const SizedBox(height: 8),
                  _RecordCard(player: row, recent: info.recentMatches),
                  // Une seule saison n'a pas d'évolution à montrer.
                  if (_period == StatisticsPeriod.allTime && seasons != null)
                    _EvolutionCard(
                      seasons: seasons,
                      // Un gardien marque peu : ses matchs parlent mieux de
                      // lui.
                      stat: _evolutionStat ??
                          (isGoalkeeper
                              ? PlayerStat.matches
                              : PlayerStat.goals),
                      onStatChanged: (stat) =>
                          setState(() => _evolutionStat = stat),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Derniers matchs'),
          const SizedBox(height: 10),
          if (info.recentMatches.isEmpty)
            const _InlineNote(
              'Aucun match suivi dans l’application pour l’instant.',
            )
          else
            _MatchList(matches: info.recentMatches),
          // Un joueur d'effectif sans compte ne peut pas gagner de badge.
          if (info.profileId != null) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Badges'),
            const SizedBox(height: 10),
            _BadgeSection(profileId: info.profileId!),
          ],
        ],
      ),
    );
  }
}

String _ordinal(int rank) => rank == 1 ? '1er' : '${rank}e';

final _nameWordStart = RegExp(r"(^|[ '’-])(\p{L})", unicode: true);

/// « FRANÇOIS » ou « françois » deviennent « François » ; « jean-pierre »,
/// « Jean-Pierre ».
String _properCaseName(String value) =>
    value.trim().toLowerCase().replaceAllMapped(
          _nameWordStart,
          (match) => '${match[1]}${match[2]!.toUpperCase()}',
        );

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.name,
    required this.nickname,
    required this.photoUrl,
    required this.profileId,
    required this.isGoalkeeper,
  });

  final String name;
  final String? nickname;
  final String? photoUrl;
  final String? profileId;
  final bool isGoalkeeper;

  /// Part vide, à droite, du carré de la photo telle qu'elle s'affiche (voir
  /// [photoClearRightShare]). Tant que la photo n'est pas là, ou sans photo,
  /// l'avatar montre ses initiales dans un carré plus petit, centré.
  double _photoClearRight(WidgetRef ref) {
    const initials = (1 - _heroInitialsScale) / 2;
    final url = photoUrl?.trim();
    if (url == null || url.isEmpty) return initials;
    return ref.watch(heroPhotoClearRightProvider(url)).when(
          data: (share) => share ?? 0,
          loading: () => initials,
          error: (_, __) => initials,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = this.nickname;
    final badge = profileId == null
        ? null
        : ref
            .watch(statisticsBadgeEmblemsProvider)
            .asData
            ?.value[profileId]
            ?.firstOrNull;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border:
            Border.all(color: AppTheme.primaryBright.withValues(alpha: .35)),
        gradient: const RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [Color(0xFF2453B8), AppTheme.surfaceHero, Color(0xFF0D2A52)],
          stops: [0, .4, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -30,
            width: 210,
            height: 230,
            child: Opacity(
              opacity: .09,
              child: Image.asset(
                'assets/images/as_grinta_logo.webp',
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Même avatar que sur les compositions d'équipe.
                PlayerAvatar(
                  photoUrl: photoUrl,
                  name: name,
                  isGoalkeeper: isGoalkeeper,
                  size: _heroPhotoSize,
                  fallbackScale: _heroInitialsScale,
                ),
                const SizedBox(width: 12),
                Expanded(
                  // Le prénom se centre entre ce qui se voit de la photo et
                  // le badge : une photo détourée ne remplit pas son carré.
                  child: Transform.translate(
                    offset: Offset(
                      -_photoClearRight(ref) * _heroPhotoSize / 2,
                      0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Une seule ligne, réduite au besoin : un prénom ne se
                        // coupe pas au milieu.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _properCaseName(name),
                            maxLines: 1,
                            style: const TextStyle(
                              fontFamily: _display,
                              fontSize: 30,
                              height: 1.05,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (nickname != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '« $nickname »',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 12),
                  // Aussi haut que la photo, pas plus.
                  SizedBox(
                    height: _heroPhotoSize,
                    width: _heroPhotoSize /
                        badgeEmblemHeightRatio(hasStar: badge.hasStar),
                    child: FittedBox(
                      child: BadgeEmblem(
                        emoji: badge.emoji,
                        imageUrl: badge.imageUrl,
                        color: badge.color,
                        baremeLabel: badge.valueLabel,
                        descriptor: badge.descriptor,
                        showStar: badge.hasStar,
                        starCount: badge.stars,
                        size: 192,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo du joueur dans l'en-tête ; le badge arboré prend la même hauteur.
const _heroPhotoSize = 96.0;

/// Taille des initiales d'un joueur sans photo, par rapport à [_heroPhotoSize].
const _heroInitialsScale = .84;

/// Or, argent et bronze pour les trois premiers du club sur une statistique.
const _gold = Color(0xFFFFD84A);
// Plus sombre que le blanc des autres rangs, pour que les deux ne se
// confondent pas.
const _silver = Color(0xFFAEBACA);
const _bronze = Color(0xFFDB9A5B);

Color _medalColor(int? rank) => switch (rank) {
      1 => _gold,
      2 => _silver,
      3 => _bronze,
      _ => AppTheme.textPrimary,
    };

/// Matchs joués exigés pour figurer au classement des moyennes (% de
/// victoires, buts par match) : sans ce seuil, un joueur venu une seule fois
/// et reparti vainqueur serait « 1er du club ».
///
/// Toutes saisons : 20 matchs. Saison précédente : 5. Saison en cours : aucun
/// tant que l'équipe a joué 5 matchs ou moins, 5 ensuite. [teamMatches] est
/// le nombre de matchs de l'équipe sur la saison en cours, quand on le
/// connaît ; à défaut, le joueur le plus présent en donne un minimum.
int averageRankingMinMatches(
  StatisticsPeriod period, {
  required int? teamMatches,
  required Iterable<PlayerStatistics> players,
}) {
  switch (period) {
    case StatisticsPeriod.allTime:
      return 20;
    case StatisticsPeriod.previous:
      return 5;
    case StatisticsPeriod.current:
      var played = teamMatches ?? 0;
      for (final p in players) {
        final matches = p.matchesPlayed ?? 0;
        if (matches > played) played = matches;
      }
      return played > 5 ? 5 : 0;
  }
}

class _BadgeSection extends ConsumerWidget {
  const _BadgeSection({required this.profileId});

  final String profileId;

  static const _columns = 4;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(playerCardBadgesProvider(profileId));
    return badges.when(
      loading: () => GrintaSkeleton.rows(itemCount: 2),
      error: (error, _) => _InlineNote(humanizeError(error)),
      data: (list) {
        if (list.isEmpty) {
          return const _InlineNote('Aucun badge gagné pour l’instant.');
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth - (_columns - 1) * _gap) / _columns;
              return Wrap(
                spacing: _gap,
                runSpacing: 14,
                children: [
                  for (final badge in list)
                    SizedBox(
                      width: width,
                      child: _BadgeTile(badge: badge, size: width),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.size});

  final ArmoireBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final def = badge.def;
    return Semantics(
      button: true,
      label: def.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showBadgeDetailSheet(context, def,
            showLadder: false, showHolders: true),
        child: Column(
          children: [
            BadgeEmblem(
              emoji: def.emoji,
              imageUrl: def.imageUrl,
              color: def.color,
              baremeLabel: baremeLabelFor(def.metric, badge.displayValue),
              descriptor: badgeDescriptorFor(
                code: def.code,
                metric: def.metric,
                category: def.category,
                name: def.name,
              ),
              showStar: def.hasStar,
              starCount: badge.stars,
              size: size,
            ),
            const SizedBox(height: 6),
            Text(
              def.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.15,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _cardDecoration = BoxDecoration(
  color: AppTheme.surface,
  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
  border: Border.all(color: AppTheme.outline.withValues(alpha: .4)),
);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontFamily: _display,
        fontSize: 15,
        letterSpacing: 1,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textFaint),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter + 4),
      children: [
        Card(
          child: GrintaEmptyState(
            icon: Icons.person_search_rounded,
            title: title,
            message: message,
          ),
        ),
      ],
    );
  }
}
