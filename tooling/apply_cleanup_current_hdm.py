from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f'{path}: expected exactly one occurrence, got {count}: {old[:80]!r}'
        )
    write(path, text.replace(old, new, 1))


# Provider wrappers with zero consumers. Keep the repository provider itself.
path = 'lib/features/sports_management/data/sport_waitlist_repository.dart'
text = read(path)
marker = 'final adminSportMatchesProvider ='
if text.count(marker) != 1:
    raise SystemExit(f'{path}: expected one dead-provider marker')
prefix, _ = text.split(marker, 1)
if not prefix.rstrip().endswith('});'):
    raise SystemExit(f'{path}: unexpected content before dead provider block')
write(path, prefix.rstrip() + '\n')

# Remove the unused prediction provider and align the HDM window on validation.
path = 'lib/features/predictions/presentation/widgets/match_history_card.dart'
replace_once(
    path,
    "import 'package:as_grinta/features/predictions/data/predictions_repository.dart';\n",
    '',
)
replace_once(
    path,
    "final historyMatchPredictionProvider = FutureProvider.autoDispose\n"
    "    .family<MatchPredictionItem?, String>((ref, matchId) {\n"
    "  return ref.watch(predictionsRepositoryProvider).fetchMatchPrediction(matchId);\n"
    "});\n\n",
    '',
)
replace_once(
    path,
    "    final now = DateTime.now();\n"
    "    final voteWindowEnd = match.kickoffAt.add(const Duration(hours: 24));\n"
    "    final voteMayStillBeOpen =\n"
    "        !now.isBefore(match.kickoffAt) && now.isBefore(voteWindowEnd);\n"
    "    final vote = voteMayStillBeOpen\n"
    "        ? ref.watch(sportMotmVoteProvider(match.id)).valueOrNull\n"
    "        : null;\n",
    "    final now = DateTime.now();\n"
    "    final validationAt = match.resultValidatedAt;\n"
    "    final voteWindowEnd = validationAt?.add(const Duration(hours: 24));\n"
    "    final voteMayStillBeOpen = validationAt != null &&\n"
    "        voteWindowEnd != null &&\n"
    "        !now.isBefore(validationAt) &&\n"
    "        now.isBefore(voteWindowEnd);\n"
    "    final vote = voteMayStillBeOpen\n"
    "        ? ref.watch(sportMotmVoteProvider(match.id)).valueOrNull\n"
    "        : null;\n",
)

# Carry the authoritative public validation timestamp in MatchModel.
path = 'lib/features/matches/domain/match_model.dart'
replace_once(
    path,
    "    this.predictionsClosedAt,\n    this.liveState,\n",
    "    this.predictionsClosedAt,\n    this.resultValidatedAt,\n    this.liveState,\n",
)
replace_once(
    path,
    "  final DateTime? predictionsClosedAt;\n\n  /// État du Tableau Blanc",
    "  final DateTime? predictionsClosedAt;\n  final DateTime? resultValidatedAt;\n\n  /// État du Tableau Blanc",
)
replace_once(
    path,
    "      predictionsClosedAt: DateTime.tryParse(\n"
    "        '${json['predictions_closed_at'] ?? ''}',\n"
    "      )?.toLocal(),\n"
    "      liveState: live['state']?.toString(),\n",
    "      predictionsClosedAt: DateTime.tryParse(\n"
    "        '${json['predictions_closed_at'] ?? ''}',\n"
    "      )?.toLocal(),\n"
    "      resultValidatedAt: DateTime.tryParse(\n"
    "        '${json['result_validated_at'] ?? ''}',\n"
    "      )?.toLocal(),\n"
    "      liveState: live['state']?.toString(),\n",
)

replace_once(
    'lib/features/matches/data/matches_repository.dart',
    "      predictions_closed_at,\n      address,\n",
    "      predictions_closed_at,\n      result_validated_at,\n      address,\n",
)

# Current user-facing HDM timing.
replace_once(
    'lib/features/admin/presentation/admin_sports_management_section.dart',
    "              '15 minutes avant le match, effectif proposé à '\n"
    "              '${feature.usualSquadSize} (modifiable match par match), scrutin '\n"
    "              'Homme du Match ouvert 1 h 45 après le coup d’envoi et fermé '\n"
    "              '24 h après le coup d’envoi.',\n",
    "              '15 minutes avant le match, effectif proposé à '\n"
    "              '${feature.usualSquadSize} (modifiable match par match), scrutin '\n"
    "              'Homme du Match ouvert après la validation du compte rendu et '\n"
    "              'disponible pendant 24 h.',\n",
)
replace_once(
    'lib/features/sports_management/presentation/sport_motm_vote_page.dart',
    "            message: 'Le vote s’ouvre 1 h 45 après le coup d’envoi.',\n",
    "            message: 'Le vote s’ouvre après la validation du compte rendu.',\n",
)

# Unit-test parsing of the validation timestamp.
path = 'test/matches_test.dart'
marker = "    test('keeps the legacy local fields as a migration fallback', () {"
test_block = """    test('keeps the server result validation instant', () {
      final match = MatchModel.fromJson({
        'id': '1',
        'season_id': 'season-1',
        'opponent_id': 'opp-1',
        'kickoff_at': '2026-08-20T18:45:00Z',
        'location': 'domicile',
        'planned_duration_minutes': 90,
        'status': 'termine',
        'result_validated_at': '2026-08-20T20:42:10Z',
      });

      expect(
        match.resultValidatedAt?.toUtc(),
        DateTime.utc(2026, 8, 20, 20, 42, 10),
      );
    });

"""
replace_once(path, marker, test_block + marker)

# Old minimal duplicate bootstrap is unreferenced after the real migration was
# added to the current isolated schema chain.
dead_bootstrap = Path('supabase/tests/bootstrap/internal_composition_schema.sql')
if not dead_bootstrap.exists():
    raise SystemExit('dead bootstrap already missing unexpectedly')
dead_bootstrap.unlink()

write(
    'supabase/tests/README.md',
    """# Tests Supabase

La suite métier utilise une pile Supabase locale et éphémère. Elle ne se connecte jamais à la production.

## Schéma de test

L’ancien historique du dépôt n’est pas entièrement rejouable depuis une base vide. Le workflow `Supabase business and RLS tests` installe donc une baseline structurelle contrôlée, puis rejoue explicitement les migrations nécessaires jusqu’aux règles actuelles, notamment Live, temporalité T−15, notifications et résultat HDM.

Les anciennes migrations de production ne sont jamais modifiées pour faciliter les tests. Quand une nouvelle migration courante dépend d’un objet absent de la baseline, la baseline est complétée avec le contrat minimal réellement présent en production ou la migration historique nécessaire est ajoutée à la chaîne de test.

## Exécution

La CI :

1. vérifie le contrat de sécurité des Edge Functions ;
2. exécute les tests de résilience de `send-push` ;
3. démarre une base Supabase locale isolée ;
4. installe le schéma métier courant ;
5. découvre et exécute **tous** les fichiers `supabase/tests/database/*.test.sql` ;
6. exécute `supabase db lint --level error`.

Les tests pgTAP sont transactionnels et annulent leurs fixtures avec `ROLLBACK`.

## Contrats actuels importants

La suite couvre notamment :

- rôles, ACL, RLS, Storage et fonctions `SECURITY DEFINER` ;
- pronostics sans ×2 et fermeture à T−15 ;
- disponibilités et gestion sportive ;
- Effectif, Composition, Live et joueurs ajoutés tardivement ;
- matchs entre nous ;
- météo ;
- finalisation et cycle HDM ancré sur la validation pendant 24 h ;
- ouverture **et résultat** HDM sous le contrat de notifications actuel ;
- signaux Realtime partagés ;
- statistiques, saisons et historique.

Une nouvelle règle Supabase n’est considérée couverte que si la migration qui la définit est effectivement installée dans la base éphémère avant les assertions concernées.
""",
)
