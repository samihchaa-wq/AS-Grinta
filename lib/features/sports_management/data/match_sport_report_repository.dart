import 'package:as_grinta/core/network/confirmed_write.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:as_grinta/features/sports_management/domain/match_sport_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Accès au compte rendu de match : une lecture, une validation.
abstract interface class MatchSportReportRepository {
  Future<MatchSportReport> fetch(String matchId);

  /// Buts définitifs d'un match validé, pour la fiche publique.
  Future<List<MatchGoalAction>> fetchGoalActions(String matchId);

  /// Envoie le compte rendu complet. Le serveur en dérive les statistiques et
  /// valide (ou corrige) le match en une seule opération.
  ///
  /// [knownVersion] est la version affichée avant l'envoi. Elle sert à
  /// reconnaître notre propre écriture si l'accusé de réception se perd :
  /// seule une version strictement supérieure prouve qu'elle a abouti. Sans
  /// elle, une relecture ne distinguerait pas l'état d'avant de l'état
  /// d'après. Lève [WriteOutcomeUnknown] quand l'issue reste indéterminée ;
  /// l'appelant ne doit alors ni annoncer un échec ni renvoyer la mutation,
  /// qui serait enregistrée comme une correction.
  Future<MatchSportReport> submit({
    required String matchId,
    required int knownVersion,
    required int scoreAsGrinta,
    required int scoreAdverse,
    required MatchComposition lineup,
    required List<MatchGoalAction> goalActions,
    String? reason,
  });

  /// Rattache un joueur qui n'avait pas encore de participation à ce match.
  Future<MatchSportReport> attachPlayer({
    required String matchId,
    String? seasonPlayerId,
    String? guestPlayerId,
    String? firstName,
    String? lastName,
    bool isGoalkeeper = false,
    String? reason,
  });
}

class SupabaseMatchSportReportRepository implements MatchSportReportRepository {
  SupabaseMatchSportReportRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MatchSportReport> fetch(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_sport_report',
      params: {'p_match_id': matchId},
    );
    return MatchSportReport.fromRpc(response);
  }

  @override
  Future<List<MatchGoalAction>> fetchGoalActions(String matchId) async {
    final response = await _client.rpc(
      'get_match_sport_goal_actions',
      params: {'p_match_id': matchId},
    );
    if (response is! List) return const [];
    return [
      for (var index = 0; index < response.length; index += 1)
        MatchGoalAction.fromJson(
          Map<String, dynamic>.from(response[index] as Map),
          index,
        ),
    ];
  }

  @override
  Future<MatchSportReport> submit({
    required String matchId,
    required int knownVersion,
    required int scoreAsGrinta,
    required int scoreAdverse,
    required MatchComposition lineup,
    required List<MatchGoalAction> goalActions,
    String? reason,
  }) {
    return confirmWrite<MatchSportReport>(
      submit: () async {
        final response = await _client.rpc(
          'admin_submit_match_sport_report',
          params: {
            'p_match_id': matchId,
            'p_score_as_grinta': scoreAsGrinta,
            'p_score_adverse': scoreAdverse,
            'p_lineup': {
              'formation_code': lineup.formationCode,
              'entries': [
                for (final entry in lineup.entries) entry.toRpcJson(),
              ],
            },
            'p_goal_actions': [
              for (final goal in goalActions) goal.toRpcJson(),
            ],
            'p_reason': _clean(reason),
          },
        );
        return MatchSportReport.fromRpc(response);
      },
      readBack: () => fetch(matchId),
      isExpected: (current) => matchSportReportWriteLanded(
        current: current,
        knownVersion: knownVersion,
        scoreAsGrinta: scoreAsGrinta,
        scoreAdverse: scoreAdverse,
      ),
    );
  }

  @override
  Future<MatchSportReport> attachPlayer({
    required String matchId,
    String? seasonPlayerId,
    String? guestPlayerId,
    String? firstName,
    String? lastName,
    bool isGoalkeeper = false,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_attach_match_sport_report_player',
      params: {
        'p_match_id': matchId,
        'p_season_player_id': seasonPlayerId,
        'p_guest_player_id': guestPlayerId,
        'p_first_name': _clean(firstName),
        'p_last_name': _clean(lastName),
        'p_is_goalkeeper': isGoalkeeper,
        'p_reason': _clean(reason),
      },
    );
    return MatchSportReport.fromRpc(response);
  }

  String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

/// Reconnaît notre propre validation dans un compte rendu relu après une
/// coupure.
///
/// La version doit avoir strictement augmenté : c'est ce qui sépare l'écriture
/// qui vient d'aboutir d'un état antérieur portant déjà le même score. Les
/// scores sont comparés en plus, pour ne pas confondre notre envoi avec une
/// validation concurrente faite par quelqu'un d'autre.
bool matchSportReportWriteLanded({
  required MatchSportReport current,
  required int knownVersion,
  required int scoreAsGrinta,
  required int scoreAdverse,
}) {
  final finalization = current.finalization;
  return finalization.isValidated &&
      finalization.version > knownVersion &&
      finalization.scoreAsGrinta == scoreAsGrinta &&
      finalization.scoreAdverse == scoreAdverse;
}

final matchSportReportRepositoryProvider =
    Provider<MatchSportReportRepository>((ref) {
  return SupabaseMatchSportReportRepository(ref.watch(supabaseClientProvider));
});

/// Buts définitifs d'un match, tels qu'affichés dans « Faits du match ».
final matchGoalActionsProvider = FutureProvider.autoDispose
    .family<List<MatchGoalAction>, String>((ref, matchId) {
  return ref
      .watch(matchSportReportRepositoryProvider)
      .fetchGoalActions(matchId);
});
