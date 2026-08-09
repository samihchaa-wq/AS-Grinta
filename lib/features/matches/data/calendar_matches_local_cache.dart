import 'dart:convert';

import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cache local léger des matchs déjà chargés.
///
/// Supabase reste toujours la source de vérité : ce cache sert uniquement à
/// afficher immédiatement le dernier état connu pendant le rafraîchissement
/// réseau suivant.
class CalendarMatchesLocalCache {
  const CalendarMatchesLocalCache();

  static const _version = 1;
  static const _keyPrefix = 'calendar_matches_v$_version';

  String? get _userScopedKey {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;
    return '${_keyPrefix}_$userId';
  }

  Future<List<MatchModel>> read() async {
    final key = _userScopedKey;
    if (key == null) return const [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      return decoded
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(MatchModel.fromJson)
          .where((match) => match.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(List<MatchModel> matches) async {
    final key = _userScopedKey;
    if (key == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(matches.map(_toJson).toList(growable: false)),
      );
    } catch (_) {
      // Le cache local ne doit jamais empêcher le fonctionnement réseau.
    }
  }

  Map<String, dynamic> _toJson(MatchModel match) {
    return {
      'id': match.id,
      'season_id': match.seasonId,
      'opponent_id': match.opponentId,
      'kickoff_at': match.kickoffAt.toUtc().toIso8601String(),
      'location': match.isHome ? 'domicile' : 'exterieur',
      'planned_duration_minutes': match.plannedDurationMinutes,
      'status': match.status,
      'score_as_grinta': match.grintaScore,
      'score_adverse': match.opponentScore,
      'predictions_closed_at':
          match.predictionsClosedAt?.toUtc().toIso8601String(),
      'result_validated_at':
          match.resultValidatedAt?.toUtc().toIso8601String(),
      'address': match.address,
      'match_type': match.matchType,
      'jersey_note': match.jerseyNote,
      'created_by': match.createdBy,
      'created_at': match.createdAt?.toUtc().toIso8601String(),
      'updated_at': match.updatedAt?.toUtc().toIso8601String(),
      'opponents': match.opponentName == null
          ? null
          : <String, dynamic>{'name': match.opponentName},
      'seasons': match.seasonName == null
          ? null
          : <String, dynamic>{'name': match.seasonName},
      'match_odds': <String, dynamic>{
        'odds_victoire_as_grinta': match.oddsWin,
        'odds_nul': match.oddsDraw,
        'odds_victoire_adverse': match.oddsLoss,
      },
      'match_live_sessions': <String, dynamic>{
        'state': match.liveState,
        'finished_at': match.liveFinishedAt?.toUtc().toIso8601String(),
        'exported': match.liveExported,
      },
    };
  }
}
