import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CompletedMatchPresenceStatus { present, absent }

class CompletedMatchEffectifPlayer {
  const CompletedMatchEffectifPlayer({
    required this.displayName,
    required this.status,
    required this.isGuest,
  });

  final String displayName;
  final CompletedMatchPresenceStatus status;
  final bool isGuest;
}

class CompletedMatchEffectif {
  const CompletedMatchEffectif({required this.players});

  factory CompletedMatchEffectif.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Effectif final invalide.');
    }
    final json = Map<String, dynamic>.from(raw);
    final players = (json['players'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .map((row) {
          final status = switch (row['presence_status']?.toString()) {
            'present' => CompletedMatchPresenceStatus.present,
            'absent' => CompletedMatchPresenceStatus.absent,
            _ => null,
          };
          final name = (row['display_name'] ?? '').toString().trim();
          if (status == null || name.isEmpty) return null;
          return CompletedMatchEffectifPlayer(
            displayName: name,
            status: status,
            isGuest: row['is_guest'] == true,
          );
        })
        .whereType<CompletedMatchEffectifPlayer>()
        .toList(growable: false);
    return CompletedMatchEffectif(players: players);
  }

  factory CompletedMatchEffectif.fromNames({
    required List<String> presentNames,
    required List<String> absentNames,
  }) {
    CompletedMatchEffectifPlayer player(
      String name,
      CompletedMatchPresenceStatus status,
    ) =>
        CompletedMatchEffectifPlayer(
          displayName: name.trim(),
          status: status,
          isGuest: false,
        );

    return CompletedMatchEffectif(
      players: [
        ...presentNames
            .where((name) => name.trim().isNotEmpty)
            .map((name) => player(name, CompletedMatchPresenceStatus.present)),
        ...absentNames
            .where((name) => name.trim().isNotEmpty)
            .map((name) => player(name, CompletedMatchPresenceStatus.absent)),
      ],
    );
  }

  List<CompletedMatchEffectifPlayer> get present => _playersWith(
        CompletedMatchPresenceStatus.present,
      );

  List<CompletedMatchEffectifPlayer> get absent => _playersWith(
        CompletedMatchPresenceStatus.absent,
      );

  bool get isEmpty => players.isEmpty;

  List<CompletedMatchEffectifPlayer> _playersWith(
    CompletedMatchPresenceStatus status,
  ) {
    final result = players.where((player) => player.status == status).toList();
    result.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
    );
    return result;
  }
}

class CompletedMatchEffectifRepository {
  CompletedMatchEffectifRepository(this._client);

  final SupabaseClient _client;

  Future<CompletedMatchEffectif?> fetch(String matchId) async {
    final response = await _client.rpc(
      'get_completed_match_effectif',
      params: {'p_match_id': matchId},
    );
    if (response == null) return null;
    return CompletedMatchEffectif.fromRpc(response);
  }
}

final completedMatchEffectifRepositoryProvider =
    Provider<CompletedMatchEffectifRepository>((ref) {
  return CompletedMatchEffectifRepository(ref.watch(supabaseClientProvider));
});

final completedMatchEffectifProvider = FutureProvider.autoDispose
    .family<CompletedMatchEffectif?, String>((ref, matchId) async {
  if (!ref.watch(sportsManagementEnabledProvider)) return null;
  return ref.watch(completedMatchEffectifRepositoryProvider).fetch(matchId);
});
