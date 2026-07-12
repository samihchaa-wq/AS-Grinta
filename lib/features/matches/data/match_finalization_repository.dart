import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un membre de l'effectif de la saison, recherchable dans la saisie rapide.
class SquadMember {
  const SquadMember({
    required this.id,
    required this.name,
    required this.isGoalkeeper,
  });

  final String id;
  final String name;
  final bool isGoalkeeper;
}

class MatchFinalizationContext {
  const MatchFinalizationContext({
    required this.squad,
    required this.isValidated,
    required this.opponentScore,
    required this.scorerGoalLines,
    required this.cleanSheetProfileId,
    required this.goalkeeperId,
    required this.goalkeeperName,
  });

  final List<SquadMember> squad;

  /// Vrai quand le match est déjà validé : la saisie sert de correction et
  /// arrive pré-remplie.
  final bool isValidated;
  final int opponentScore;

  /// Une entrée par but déjà enregistré (id du buteur, répété autant de fois
  /// qu'il a marqué) — pour reconstruire la liste des buts en correction.
  final List<String> scorerGoalLines;
  final String? cleanSheetProfileId;

  /// Le gardien de l'effectif (l’admin) pour l'interrupteur clean sheet.
  final String? goalkeeperId;
  final String? goalkeeperName;
}

class MatchFinalizationRepository {
  MatchFinalizationRepository(this._client);

  final SupabaseClient _client;

  Future<MatchFinalizationContext> fetch(String matchId) async {
    final match = await _client
        .from('matches')
        .select('season_id,status,score_adverse')
        .eq('id', matchId)
        .maybeSingle();
    if (match == null) {
      throw StateError('Ce match est introuvable ou a été supprimé.');
    }
    final seasonId = match['season_id'].toString();
    final status = (match['status'] ?? 'a_venir').toString();
    final isValidated = status == 'termine' || status == 'archive';

    final membershipRows = await _client
        .from('season_players')
        .select('id,first_name,last_name,is_goalkeeper,is_active,position')
        .eq('season_id', seasonId)
        .eq('is_active', true)
        .order('position', ascending: true, nullsFirst: false)
        .order('first_name');

    final squad = <SquadMember>[];
    String? goalkeeperId;
    String? goalkeeperName;
    for (final row in membershipRows as List) {
      final map = Map<String, dynamic>.from(row);
      final id = map['id'].toString();
      final name = _displayName(map);
      final isGoalkeeper = map['is_goalkeeper'] == true;
      squad.add(SquadMember(id: id, name: name, isGoalkeeper: isGoalkeeper));
      if (isGoalkeeper && goalkeeperId == null) {
        goalkeeperId = id;
        goalkeeperName = name;
      }
    }

    final scorerGoalLines = <String>[];
    String? cleanSheetProfileId;
    if (isValidated) {
      final statRows = await _client
          .from('match_player_stats')
          .select('season_player_id,goals,clean_sheet')
          .eq('match_id', matchId);
      for (final row in statRows as List) {
        final map = Map<String, dynamic>.from(row);
        final id = map['season_player_id'].toString();
        final goals = (map['goals'] as num?)?.toInt() ?? 0;
        for (var i = 0; i < goals; i++) {
          scorerGoalLines.add(id);
        }
        if (map['clean_sheet'] == true) cleanSheetProfileId = id;
      }
    }

    return MatchFinalizationContext(
      squad: squad,
      isValidated: isValidated,
      opponentScore: (match['score_adverse'] as num?)?.toInt() ?? 0,
      scorerGoalLines: scorerGoalLines,
      cleanSheetProfileId: cleanSheetProfileId,
      goalkeeperId: goalkeeperId,
      goalkeeperName: goalkeeperName,
    );
  }

  String _displayName(Map<String, dynamic> player) {
    final firstName = (player['first_name'] ?? '').toString().trim();
    return firstName.isNotEmpty ? firstName : 'Joueur';
  }
}

final matchFinalizationRepositoryProvider =
    Provider<MatchFinalizationRepository>((ref) {
  return MatchFinalizationRepository(ref.watch(supabaseClientProvider));
});

final matchFinalizationContextProvider = FutureProvider.autoDispose
    .family<MatchFinalizationContext, String>((ref, matchId) {
  return ref.watch(matchFinalizationRepositoryProvider).fetch(matchId);
});
