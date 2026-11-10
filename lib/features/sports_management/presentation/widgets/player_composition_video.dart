import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/widgets/match_detail_header_card.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_kit_photo_overrides.dart';
import 'package:as_grinta/features/sports_management/domain/formation_display.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_presentation.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/stadium_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ajouté à l'adresse de la compo quand on l'ouvre depuis sa notification
/// (`?section=composition&from=notification`) : la vidéo se lance alors à
/// chaque fois, même déjà vue.
const compositionOpenedFromNotification = 'notification';

/// L'adresse d'une notification, avec la marque « ouverte depuis la
/// notification » si elle mène à une compo. Les autres adresses sont rendues
/// telles quelles.
String markCompositionRouteFromNotification(String route) {
  final uri = Uri.tryParse(route);
  if (uri == null ||
      uri.queryParameters['section'] != 'composition' ||
      !RegExp(r'^/?matches/[^/]+/lineup$').hasMatch(uri.path)) {
    return route;
  }
  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      'from': compositionOpenedFromNotification,
    },
  ).toString();
}

/// Les données de la vidéo, à partir de la compo et de la fiche du match.
/// Partagé entre l'aperçu de l'admin et la vidéo des joueurs, pour qu'ils
/// voient exactement la même chose.
CompositionPresentationData buildCompositionPresentationData({
  required String? formationCode,
  required List<MatchCompositionEntry> field,
  required List<MatchCompositionEntry> bench,
  UpcomingMatchFixtureData? fixture,
  String? fallbackOpponent,
  DateTime? fallbackKickoffAt,
  CompositionPresentationCoach? coach,
}) {
  final opponent = fixture?.opponentName ?? fallbackOpponent ?? 'Adversaire';
  final grintaIsHome = fixture?.grintaIsHome ?? true;
  return CompositionPresentationData(
    homeName: grintaIsHome ? 'AS Grinta' : opponent,
    awayName: grintaIsHome ? opponent : 'AS Grinta',
    grintaIsHome: grintaIsHome,
    field: alignFieldToFormation(formationCode, field),
    bench: bench,
    coach: coach,
    kickoffAt: fixture?.kickoffAt ?? fallbackKickoffAt,
    matchType: fixture?.matchType,
    typeLabel: fixture == null
        ? null
        : calendarMatchTypeLabel(fixture.matchType, fixture.championshipRound),
    address: fixture?.address,
    formationCode: formationCode,
  );
}

/// Retient, sur ce téléphone, les compos dont la vidéo a déjà été vue, et
/// celles publiées depuis ce téléphone.
/// - Une fois vue pour un match, elle ne se relance plus d'elle-même, même si
///   la compo est modifiée ensuite.
/// - Celui qui publie ne la voit jamais d'elle-même pour ce match, même par
///   la notification : il a son bouton « Aperçu ».
class CompositionVideoSeenStore {
  const CompositionVideoSeenStore();

  static const _prefix = 'composition_video_seen.';
  static const _publishedPrefix = 'composition_video_published_here.';

  /// La vidéo doit-elle se lancer d'elle-même à l'arrivée sur la compo ?
  Future<bool> shouldAutoplay(
    String matchId, {
    required bool fromNotification,
  }) async {
    if (await publishedHere(matchId)) return false;
    if (fromNotification) return true;
    return !await hasSeen(matchId);
  }

  Future<bool> publishedHere(String matchId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool('$_publishedPrefix$matchId') ?? false;
    } catch (_) {
      // Mémoire illisible : on ne lance rien plutôt que de surprendre celui
      // qui publie.
      return true;
    }
  }

  Future<void> markPublishedHere(String matchId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('$_publishedPrefix$matchId', true);
    } catch (_) {
      // Sans mémoire, au pire celui qui publie voit la vidéo une fois.
    }
  }

  Future<bool> hasSeen(String matchId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool('$_prefix$matchId') ?? false;
    } catch (_) {
      // Mémoire du téléphone illisible : mieux vaut ne pas relancer la vidéo
      // à chaque visite.
      return true;
    }
  }

  Future<void> markSeen(String matchId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('$_prefix$matchId', true);
    } catch (_) {
      // Sans mémoire, la vidéo se relancera à la prochaine visite : rien de
      // grave.
    }
  }
}

/// Retrouve la photo d'une fiche de la saison (le coach, côté joueur : la
/// liste des présents ne la donne pas). Profil d'abord, fiche ensuite, comme
/// la fiche joueur. `null` : pas de photo, la vidéo montre une silhouette.
typedef SeasonPlayerPhotoLookup = Future<String?> Function(
  String seasonPlayerId,
);

final seasonPlayerPhotoLookupProvider =
    Provider<SeasonPlayerPhotoLookup>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return (seasonPlayerId) async {
    final row = await client
        .from('season_players')
        .select('photo_url, profiles!season_players_profile_id_fkey(photo_url)')
        .eq('id', seasonPlayerId)
        .maybeSingle();
    if (row == null) return null;
    String? clean(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final profile = row['profiles'];
    return clean(profile is Map ? profile['photo_url'] : null) ??
        clean(row['photo_url']);
  };
});

final compositionVideoSeenStoreProvider =
    Provider<CompositionVideoSeenStore>((ref) {
  return const CompositionVideoSeenStore();
});

/// Onglet Compo d'un joueur : la compo publiée, le bouton « Aperçu de la
/// vidéo » (illimité), et la vidéo lancée d'elle-même
/// - à chaque ouverture depuis la notification de la compo ;
/// - à la première visite de l'onglet après la publication (une compo
///   modifiée ensuite ne la relance pas).
class PlayerCompositionTab extends ConsumerStatefulWidget {
  const PlayerCompositionTab({
    super.key,
    required this.matchId,
    required this.lineupBuilder,
    this.fromNotification = false,
  });

  final String matchId;

  /// La compo publiée telle que l'onglet l'affiche, avec sur son terrain les
  /// repères où la vidéo se pose.
  final Widget Function(CompositionLanding landing) lineupBuilder;
  final bool fromNotification;

  @override
  ConsumerState<PlayerCompositionTab> createState() =>
      _PlayerCompositionTabState();
}

class _PlayerCompositionTabState extends ConsumerState<PlayerCompositionTab> {
  /// Version de compo déjà examinée pour le lancement automatique : une seule
  /// tentative par compo affichée.
  int? _autoChecked;
  bool _playing = false;
  final CompositionLanding _landing = CompositionLanding();

  @override
  void didUpdateWidget(covariant PlayerCompositionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Une nouvelle notification sur le même écran relance l'examen.
    if (widget.fromNotification && !oldWidget.fromNotification) {
      _autoChecked = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final composition = ref
        .watch(publishedMatchCompositionProvider(widget.matchId))
        .valueOrNull;
    final playable = composition != null &&
        composition.entriesFor(MatchCompositionZone.field).any(
              (entry) => !entry.isVacant,
            );
    if (playable && _autoChecked != composition.version) {
      _autoChecked = composition.version;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_autoplay(composition)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.lineupBuilder(_landing),
        if (playable) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: _playing
                  ? null
                  : () {
                      // Pendant l'appui, avant toute attente : débloque la
                      // vidéo du stade.
                      primeStadiumVideo();
                      unawaited(_play(composition));
                    },
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Aperçu de la vidéo'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _autoplay(MatchComposition composition) async {
    if (!mounted) return;
    final store = ref.read(compositionVideoSeenStoreProvider);
    final fromNotification = widget.fromNotification;
    if (!await store.shouldAutoplay(
      widget.matchId,
      fromNotification: fromNotification,
    )) {
      return;
    }
    if (!mounted) return;
    // Une autre page ouverte par-dessus : pas de vidéo dans son dos.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (fromNotification) {
      // L'adresse perd sa marque : revenir sur la page ou la recharger ne
      // relance pas la vidéo.
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        router.replace(
          '/matches/${widget.matchId}/lineup?section=composition',
        );
      }
    }
    await _play(composition);
  }

  Future<void> _play(MatchComposition composition) async {
    if (_playing) return;
    setState(() => _playing = true);
    try {
      final store = ref.read(compositionVideoSeenStoreProvider);
      // Vue dès qu'elle démarre : la fermer tout de suite compte aussi.
      unawaited(store.markSeen(widget.matchId));
      final data = await _loadData(composition);
      if (!mounted) return;
      await showCompositionPresentation(
        context,
        data: data,
        landing: _landing,
      );
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<CompositionPresentationData> _loadData(
    MatchComposition composition,
  ) async {
    final matchId = widget.matchId;
    UpcomingMatchFixtureData? fixture;
    try {
      fixture = await ref
          .read(upcomingMatchFixtureProvider(matchId).future)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Sans la fiche du match, l'accroche se contente de l'effectif.
    }
    CompositionPresentationCoach? coach;
    String? coachSeasonPlayerId;
    DateTime? kickoffAt;
    try {
      final board = await ref
          .read(matchAvailabilityBoardProvider(matchId).future)
          .timeout(const Duration(seconds: 4));
      kickoffAt = board?.kickoffAt;
      // Le coach n'apparaît que s'il s'est dit présent.
      final present = board?.players.where(
        (player) =>
            player.isCoach &&
            player.status == MatchAvailabilityBoardStatus.present,
      );
      final player = present == null || present.isEmpty ? null : present.first;
      if (player != null) {
        String? photoUrl;
        final seasonPlayerId = player.seasonPlayerId;
        coachSeasonPlayerId = seasonPlayerId;
        if (seasonPlayerId != null) {
          try {
            photoUrl = await ref
                .read(seasonPlayerPhotoLookupProvider)(seasonPlayerId)
                .timeout(const Duration(seconds: 3));
          } catch (_) {
            // Sans photo, le coach garde sa silhouette.
          }
        }
        coach = CompositionPresentationCoach(
          id: player.participantId,
          name: player.firstNameOnly,
          photoUrl: photoUrl,
        );
      }
    } catch (_) {
      // Sans l'effectif, la vidéo se passe de l'écran du coach.
    }
    // La vidéo et le terrain utilisent les mêmes photos du maillot choisi.
    var kitPhotos = const <String, String>{};
    try {
      // Wait for the actual match kit instead of briefly showing France
      // when a slow connection exceeds the old four-second timeout.
      kitPhotos =
          await ref.read(matchKitPhotoOverridesProvider(matchId).future);
    } catch (_) {
      // Les portraits France restent toujours disponibles en repli.
    }
    return buildCompositionPresentationData(
      formationCode: composition.formationCode,
      field: withMatchKitPhotos(
          composition.entriesFor(MatchCompositionZone.field), kitPhotos),
      bench: withMatchKitPhotos(
          composition.entriesFor(MatchCompositionZone.bench), kitPhotos),
      fixture: fixture,
      fallbackKickoffAt: kickoffAt,
      coach: coach == null
          ? null
          : CompositionPresentationCoach(
              id: coach.id,
              name: coach.name,
              photoUrl: coachPhotoForMatchKit(
                seasonPlayerId: coachSeasonPlayerId,
                francePhotoUrl: coach.photoUrl,
                photoOverrides: kitPhotos,
              ),
            ),
    );
  }
}
