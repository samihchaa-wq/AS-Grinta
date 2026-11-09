import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_kit_photo_overrides.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/effectif_avatar_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchAvailabilityBoardCard extends ConsumerWidget {
  const MatchAvailabilityBoardCard({
    super.key,
    required this.matchId,
    this.bottomSpacing = 0,
    this.compact = false,
    this.showAfterComposition = false,
  });

  final String matchId;
  final double bottomSpacing;
  final bool compact;
  final bool showAfterComposition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(sportsManagementEnabledProvider)) {
      return const SizedBox.shrink();
    }

    final boardAsync = ref.watch(matchAvailabilityBoardProvider(matchId));
    final kitPhotosAsync = ref.watch(matchKitPhotoOverridesProvider(matchId));
    // Never paint France portraits before the match-specific kit is resolved.
    if (kitPhotosAsync.isLoading) return const SizedBox.shrink();
    final kitPhotos = kitPhotosAsync.valueOrNull ?? const <String, String>{};
    final isInternal =
        ref.watch(matchInfoProvider(matchId)).valueOrNull?.isInternal ?? false;
    return boardAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => Padding(
        padding: EdgeInsets.only(bottom: bottomSpacing),
        child: Card(
          margin: compact ? EdgeInsets.zero : null,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline),
                SizedBox(width: 10),
                Expanded(child: Text('Effectif momentanément indisponible.')),
              ],
            ),
          ),
        ),
      ),
      data: (board) {
        final now = DateTime.now();
        final visible = board != null &&
            (board.isVisibleAt(now) ||
                (showAfterComposition && now.isBefore(board.kickoffAt)));
        if (!visible) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: bottomSpacing),
          child: MatchAvailabilityBoardContent(
            board: board,
            isInternal: isInternal,
            kitPhotos: kitPhotos,
            headerMargin: compact ? EdgeInsets.zero : null,
          ),
        );
      },
    );
  }
}

class MatchAvailabilityBoardContent extends StatelessWidget {
  const MatchAvailabilityBoardContent({
    super.key,
    required this.board,
    this.isInternal = false,
    this.kitPhotos = const <String, String>{},
    this.headerMargin,
  });

  final MatchAvailabilityBoard board;
  final Map<String, String> kitPhotos;

  /// Marge de l'encadré d'en-tête (celle d'une carte par défaut).
  final EdgeInsetsGeometry? headerMargin;

  /// Match entre nous : pas de liste d'attente ni de limite, comme sur la
  /// page des admins.
  final bool isInternal;

  @override
  Widget build(BuildContext context) {
    final convoked = board.convoked;
    final absent = board.playersWith(MatchAvailabilityBoardStatus.absent);
    final noResponse = board.playersWith(
      MatchAvailabilityBoardStatus.noResponse,
    );
    // Le coach est dans l'effectif mais ne prend la place d'aucun joueur :
    // il ne doit pas déclencher l'alerte de dépassement.
    final coaches = convoked.where((player) => player.isCoach).length;
    final overLimit =
        !isInternal && convoked.length - coaches > board.squadSizeLimit;
    // Même disposition que la page des admins : un encadré d'en-tête, puis
    // les colonnes en pleine largeur, pour que les prénoms aient la même
    // place.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: headerMargin,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.groups_2_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Effectif',
                        style: Theme.of(
                          context,
                        )
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w400),
                      ),
                    ),
                    if (overLimit)
                      const Tooltip(
                        message: 'La limite indicative est dépassée',
                        child: Icon(Icons.warning_amber_rounded,
                            color: Colors.orange),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  isInternal
                      ? 'Mise à jour en direct'
                      : 'Mise à jour en direct · limite indicative '
                          '${board.squadSizeLimit}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Mêmes colonnes, mêmes titres, même ordre et même façon de compter
        // que sur la page des admins, en lecture seule.
        EffectifColumnsLayout(
          columns: [
            _BoardGroup(
              title: 'Convoqués',
              countLabel: effectifCountText(
                total: convoked.length,
                coaches: coaches,
              ),
              players: convoked,
              kitPhotos: kitPhotos,
              color: AppTheme.availabilityIn,
              icon: Icons.check_circle_outline,
            ),
            if (!isInternal)
              _BoardGroup(
                title: 'Liste d’attente',
                players: board.waitlisted,
                kitPhotos: kitPhotos,
                color: AppTheme.availabilityWaiting,
                icon: Icons.hourglass_top_rounded,
              ),
            _BoardGroup(
              title: 'Absents',
              players: absent,
              kitPhotos: kitPhotos,
              color: AppTheme.availabilityOut,
              icon: Icons.cancel_outlined,
            ),
            _BoardGroup(
              title: 'Sans réponse',
              players: noResponse,
              kitPhotos: kitPhotos,
              color: AppTheme.availabilityUnknown,
              icon: Icons.schedule_outlined,
            ),
          ],
        ),
      ],
    );
  }
}

class _BoardGroup extends StatelessWidget {
  const _BoardGroup({
    required this.title,
    required this.players,
    required this.kitPhotos,
    required this.color,
    required this.icon,
    this.countLabel,
  });

  final String title;
  final List<MatchAvailabilityBoardPlayer> players;
  final Map<String, String> kitPhotos;
  final Color color;
  final IconData icon;

  /// Par défaut, le simple nombre de joueurs.
  final String? countLabel;

  /// Couleur de chaque prénom selon sa réponse, comme chez les admins.
  Color _playerColor(MatchAvailabilityBoardPlayer player) =>
      switch (player.status) {
        MatchAvailabilityBoardStatus.present => AppTheme.availabilityIn,
        MatchAvailabilityBoardStatus.absent => AppTheme.availabilityOut,
        MatchAvailabilityBoardStatus.noResponse => AppTheme.availabilityUnknown,
        MatchAvailabilityBoardStatus.ignored => color,
      };

  @override
  Widget build(BuildContext context) {
    return EffectifSectionFrame(
      title: title,
      countLabel: countLabel ?? '${players.length}',
      color: color,
      icon: icon,
      child: players.isEmpty
          ? const EffectifEmptyLabel()
          : EffectifAvatarGrid(
              children: [
                for (final player in players)
                  Semantics(
                    label: player.firstNameOnly,
                    excludeSemantics: true,
                    child: EffectifPlayerTile(
                      key: ValueKey('board-player-${player.participantId}'),
                      photoUrl:
                          kitPhotos[player.seasonPlayerId] ?? player.photoUrl,
                      name: player.firstNameOnly,
                      lastName: player.lastName,
                      isGoalkeeper: player.isGoalkeeper,
                      isCoach: player.isCoach,
                      color: _playerColor(player),
                    ),
                  ),
              ],
            ),
    );
  }
}
