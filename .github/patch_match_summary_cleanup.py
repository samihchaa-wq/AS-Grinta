from pathlib import Path
import re


def sub(path: str, pattern: str, replacement: str, label: str) -> None:
    file = Path(path)
    text = file.read_text()
    updated, count = re.subn(
        pattern,
        lambda _: replacement,
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        Path('.patch_error.txt').write_text(
            f'Pattern not found: {label} in {path} ({count})\n'
        )
        raise SystemExit(f'Pattern not found: {label} in {path} ({count})')
    file.write_text(updated)


home = 'lib/features/home/presentation/accueil_page.dart'
sub(
    home,
    r"onTap: \(\) => context\.push\(\s*open \? '/matches/\$\{match\.id\}/prediction' : '/matches/\$\{match\.id\}',\s*\),",
    "onTap: () => context.push('/matches/${match.id}'),",
    'next match card route',
)

repo = 'lib/features/matches/data/match_details_repository.dart'
sub(
    repo,
    r'class MatchPredictionResult \{',
    """class MatchStartingPlayer {
  const MatchStartingPlayer({
    required this.seasonPlayerId,
    required this.name,
    required this.goals,
    required this.isManOfTheMatch,
    required this.sortOrder,
  });

  final String? seasonPlayerId;
  final String name;
  final int goals;
  final bool isManOfTheMatch;
  final int sortOrder;
}

class MatchPredictionResult {""",
    'starting player model',
)
sub(
    repo,
    r'required this\.playerStats,\s*required this\.predictions,',
    'required this.playerStats,\n    required this.startingLineup,\n    required this.predictions,',
    'details constructor lineup',
)
sub(
    repo,
    r'final List<MatchStatLine> playerStats;\s*final List<MatchPredictionResult> predictions;',
    'final List<MatchStatLine> playerStats;\n  final List<MatchStartingPlayer> startingLineup;\n  final List<MatchPredictionResult> predictions;',
    'details lineup field',
)
sub(
    repo,
    r'var playerStats = const <MatchStatLine>\[\];\s*var predictions = const <MatchPredictionResult>\[\];',
    'var playerStats = const <MatchStatLine>[];\n    var startingLineup = const <MatchStartingPlayer>[];\n    var predictions = const <MatchPredictionResult>[];',
    'details lineup variable',
)
sub(
    repo,
    r"      final statRows = await _client\.from\('match_player_stats'\)\.select\('''.*?      final pointRows = await _client",
    """      final statRows = await _client.from('match_player_stats').select('''
        season_player_id,goals,clean_sheet,
        season_players(first_name,last_name)
      ''').eq('match_id', matchId);
      final statsByPlayerId = <String, MatchStatLine>{};
      playerStats = (statRows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final player = map['season_players'] is Map
            ? Map<String, dynamic>.from(map['season_players'] as Map)
            : const <String, dynamic>{};
        final stat = MatchStatLine(
          name: _displayName(player),
          goals: (map['goals'] as num?)?.toInt() ?? 0,
          cleanSheet: map['clean_sheet'] == true,
        );
        final seasonPlayerId = map['season_player_id']?.toString();
        if (seasonPlayerId != null && seasonPlayerId.isNotEmpty) {
          statsByPlayerId[seasonPlayerId] = stat;
        }
        return stat;
      }).toList()
        ..sort((a, b) => b.goals.compareTo(a.goals));

      final publication = await _client
          .from('match_composition_publications')
          .select('snapshot')
          .eq('match_id', matchId)
          .order('version', ascending: false)
          .order('published_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final manOfMatchRows = await _client
          .from('match_man_of_match')
          .select('season_player_id')
          .eq('match_id', matchId);
      final manOfMatchIds = {
        for (final raw in manOfMatchRows as List)
          if ((raw as Map)['season_player_id'] != null)
            raw['season_player_id'].toString(),
      };
      final snapshot = publication?['snapshot'];
      if (snapshot is Map && snapshot['entries'] is List) {
        startingLineup = (snapshot['entries'] as List)
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .where((entry) => entry['zone']?.toString() == 'field')
            .map((entry) {
              final seasonPlayerId = entry['season_player_id']?.toString();
              final stat = seasonPlayerId == null
                  ? null
                  : statsByPlayerId[seasonPlayerId];
              return MatchStartingPlayer(
                seasonPlayerId: seasonPlayerId,
                name: _firstNameFromText(
                  (entry['display_name'] ?? 'Joueur').toString(),
                ),
                goals: stat?.goals ?? 0,
                isManOfTheMatch: seasonPlayerId != null &&
                    manOfMatchIds.contains(seasonPlayerId),
                sortOrder: (entry['sort_order'] as num?)?.toInt() ?? 0,
              );
            })
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }

      final pointRows = await _client""",
    'validated stats and starting lineup',
)
sub(
    repo,
    r'playerStats: playerStats,\s*predictions: predictions,',
    'playerStats: playerStats,\n      startingLineup: startingLineup,\n      predictions: predictions,',
    'return starting lineup',
)
sub(
    repo,
    r"  static String _displayName\(Map<String, dynamic> profile\) \{.*?\n  \}\n\n  Future<void> reportMatch",
    """  static String _displayName(Map<String, dynamic> profile) {
    final firstName = (profile['first_name'] ?? '').toString().trim();
    return firstName.isEmpty ? 'Joueur' : firstName;
  }

  static String _firstNameFromText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Joueur';
    return trimmed.split(RegExp(r'\\s+')).first;
  }

  Future<void> reportMatch""",
    'first name helper',
)

page = 'lib/features/matches/presentation/match_details_page.dart'
sub(
    page,
    r'\s*if \(details\.playerStats\.isNotEmpty\) \.\.\.\[\s*const SizedBox\(height: 16\),\s*_MatchSummary\(details: details\),\s*\],',
    '\n                const SizedBox(height: 16),\n                _MatchSummary(details: details),',
    'always show match summary',
)
sub(
    page,
    r'class _MatchSummary extends StatelessWidget \{.*?\n\}\n\nclass _SportAction',
    """class _MatchSummary extends StatelessWidget {
  const _MatchSummary({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Résumé du match',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Composition de départ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (details.startingLineup.isEmpty)
              const Text('Composition de départ non renseignée.')
            else
              ...details.startingLineup.map(
                (player) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(player.name)),
                      if (player.goals > 0) ...[
                        Text(
                          player.goals == 1
                              ? '⚽️'
                              : '⚽️ ×${player.goals}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (player.isManOfTheMatch)
                        const Text('👑', style: TextStyle(fontSize: 18)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SportAction""",
    'match summary lineup',
)

admin = 'lib/features/sports_management/presentation/admin_squad_plan_page.dart'
sub(
    admin,
    r'  void _applyAutomaticProposal\(\) \{.*?\n  \}\n\n  Future<void> _showPlayerActions',
    '  Future<void> _showPlayerActions',
    'automatic proposal method',
)
sub(
    admin,
    r'  Future<void> _configureLimit\(\) async \{.*?\n  \}\n\n  Future<void> _recomputeProposal\(\) async \{.*?\n  \}\n\n  Future<void> _sendReminder',
    '  Future<void> _sendReminder',
    'limit and recompute methods',
)
sub(
    admin,
    r'\s*onLimit: _configureLimit,\s*onRecompute: _recomputeProposal,\s*onAutoPlace: _applyAutomaticProposal,\s*onReminder: _sendReminder,',
    '\n          onReminder: _sendReminder,',
    'summary callbacks invocation',
)
sub(
    admin,
    r'\s*required this\.onLimit,\s*required this\.onRecompute,\s*required this\.onAutoPlace,\s*required this\.onReminder,',
    '\n    required this.onReminder,',
    'summary constructor callbacks',
)
sub(
    admin,
    r'\s*final VoidCallback onLimit;\s*final VoidCallback onRecompute;\s*final VoidCallback onAutoPlace;\s*final VoidCallback onReminder;',
    '\n  final VoidCallback onReminder;',
    'summary callback fields',
)
sub(
    admin,
    r"\s*const SizedBox\(height: 12\),\s*Wrap\(\s*spacing: 8,\s*runSpacing: 8,\s*children: \[\s*Chip\(label: Text\('\$\{composition\.fieldCount\}/11 titulaires'\)\),.*?Chip\(label: Text\('Version \$\{composition\.version\}'\)\),\s*\],\s*\),",
    "\n            if (composition.version > 0) ...[\n              const SizedBox(height: 12),\n              Chip(label: Text('Version ${composition.version}')),\n            ],",
    'selection count chips',
)
sub(
    admin,
    r"\s*OutlinedButton\.icon\(\s*onPressed: busy \? null : onLimit,.*?label: const Text\('Placer la proposition'\),\s*\),",
    '',
    'three removed actions',
)
sub(
    admin,
    r'label: Text\(player\.displayName\),',
    """label: Text(
                    player.firstName.trim().isEmpty
                        ? player.displayName
                        : player.firstName.trim(),
                  ),""",
    'availability first names',
)
