from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"Pattern not found in {path}: {old[:160]!r}")
    file.write_text(text.replace(old, new, 1))


def replace_regex(path: str, pattern: str, replacement: str) -> None:
    file = Path(path)
    text = file.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Regex matched {count} times in {path}: {pattern[:160]!r}")
    file.write_text(updated)


# Include finished matches in the existing admin workspace.
replace_once(
    "lib/features/sports_management/data/sport_waitlist_repository.dart",
    ".eq('status', 'a_venir')\n        .order('kickoff_at');",
    ".inFilter('status', const ['a_venir', 'termine'])\n        .order('kickoff_at', ascending: false);",
)

# Enrich finalization participants so the post-match editor starts with the
# same player presentation metadata as the published composition.
finalization_model = "lib/features/sports_management/domain/sport_match_finalization.dart"
replace_once(
    finalization_model,
    "    this.seasonPlayerId,\n    this.guestPlayerId,\n  });",
    "    this.seasonPlayerId,\n    this.guestPlayerId,\n    this.photoUrl,\n    this.isMotm = false,\n  });",
)
replace_once(
    finalization_model,
    "      cleanSheet: json['clean_sheet'] == true,\n    );",
    "      cleanSheet: json['clean_sheet'] == true,\n      photoUrl: _nullableText(json['photo_url']),\n      isMotm: json['is_motm'] == true,\n    );",
)
replace_once(
    finalization_model,
    "  final bool cleanSheet;\n\n  SportFinalParticipant copyWith({",
    "  final bool cleanSheet;\n  final String? photoUrl;\n  final bool isMotm;\n\n  SportFinalParticipant copyWith({",
)
replace_once(
    finalization_model,
    "      cleanSheet: nextPresent ? (cleanSheet ?? this.cleanSheet) : false,\n    );",
    "      cleanSheet: nextPresent ? (cleanSheet ?? this.cleanSheet) : false,\n      photoUrl: photoUrl,\n      isMotm: isMotm,\n    );",
)

# Preserve photo/goals/MOTM whenever an entry moves and add a post-match
# initializer built from the finalization snapshot, not convocations.
composition_model = "lib/features/sports_management/domain/match_composition.dart"
replace_once(
    composition_model,
    "import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';",
    "import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';\nimport 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';",
)
replace_once(
    composition_model,
    "      slotLabel: slotLabel,\n      sortOrder: sortOrder ?? this.sortOrder,",
    "      slotLabel: slotLabel,\n      photoUrl: photoUrl,\n      goals: goals,\n      isMotm: isMotm,\n      sortOrder: sortOrder ?? this.sortOrder,",
)
replace_once(
    composition_model,
    "  final String matchId;\n",
    "  factory MatchComposition.initialFromFinalization({\n    required SportMatchFinalization finalization,\n  }) {\n    return MatchComposition(\n      matchId: finalization.matchId,\n      formationCode: null,\n      status: 'draft',\n      version: 0,\n      hasUnpublishedChanges: true,\n      squadSizeExceptionApproved: false,\n      entries: [\n        for (var index = 0; index < finalization.participants.length; index += 1)\n          _initialPostMatchEntry(finalization.participants[index], index),\n      ],\n    );\n  }\n\n  final String matchId;\n",
)
replace_once(
    composition_model,
    "Map<String, dynamic> _map(Object? raw) {",
    "MatchCompositionEntry _initialPostMatchEntry(\n  SportFinalParticipant participant,\n  int index,\n) {\n  final selected = participant.present;\n  return MatchCompositionEntry(\n    participantId: participant.participantId,\n    seasonPlayerId: participant.seasonPlayerId ?? '',\n    guestPlayerId: participant.guestPlayerId,\n    displayName: participant.displayName.trim(),\n    isGuest: participant.isGuest,\n    isGoalkeeper: participant.isGoalkeeper,\n    zone: selected\n        ? MatchCompositionZone.bench\n        : MatchCompositionZone.notSelected,\n    photoUrl: participant.photoUrl,\n    goals: participant.goals,\n    isMotm: participant.isMotm,\n    sortOrder: index,\n    availabilityStatus: selected ? 'available' : 'absent',\n    convocationStatus: selected ? 'convoked' : 'not_convoked',\n    selectionStatus: selected ? 'substitute' : 'not_selected',\n  );\n}\n\nMap<String, dynamic> _map(Object? raw) {",
)

# Add the atomic one-shot post-match RPC to the composition repository.
composition_repo = "lib/features/sports_management/data/match_composition_repository.dart"
replace_once(
    composition_repo,
    "  Future<MatchComposition> publishComposition({",
    "  Future<MatchComposition> createPostMatchComposition({\n    required MatchComposition composition,\n    required bool allowSquadSizeException,\n    String? reason,\n  });\n  Future<MatchComposition> publishComposition({",
)
replace_once(
    composition_repo,
    "  @override\n  Future<MatchComposition> publishComposition({",
    "  @override\n  Future<MatchComposition> createPostMatchComposition({\n    required MatchComposition composition,\n    required bool allowSquadSizeException,\n    String? reason,\n  }) async {\n    final response = await _client.rpc(\n      'admin_create_postmatch_composition',\n      params: {\n        'p_match_id': composition.matchId,\n        'p_formation_code': _clean(composition.formationCode),\n        'p_entries': [\n          for (final entry in composition.entries) entry.toRpcJson(),\n        ],\n        'p_allow_squad_size_exception': allowSquadSizeException,\n        'p_reason': _clean(reason),\n      },\n    );\n    final published = MatchComposition.tryFromRpc(response);\n    if (published == null) {\n      throw const FormatException('Composition post-match invalide.');\n    }\n    return published;\n  }\n\n  @override\n  Future<MatchComposition> publishComposition({",
)

# Reuse the existing editor with finalization participants and a one-time lock.
page = "lib/features/sports_management/presentation/admin_squad_plan_page.dart"
replace_once(
    page,
    "import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';",
    "import 'package:as_grinta/features/sports_management/data/sport_match_finalization_repository.dart';\nimport 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';",
)
replace_once(
    page,
    "import 'package:as_grinta/features/sports_management/domain/match_composition.dart';",
    "import 'package:as_grinta/features/sports_management/domain/match_composition.dart';\nimport 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';",
)
replace_once(
    page,
    "  MatchComposition? _composition;\n  Set<String> _desiredConvoked = {};",
    "  MatchComposition? _composition;\n  SportMatchFinalization? _finalization;\n  Set<String> _desiredConvoked = {};\n  Set<String> _actualPresent = {};\n  bool _postMatch = false;\n  bool _compositionExisted = false;",
)
replace_regex(
    page,
    r"  Future<void> _loadWorkspace\(String matchId\) async \{.*?\n  \}\n\n  /// Relance de disponibilité",
    """  Future<void> _loadWorkspace(String matchId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final waitlistRepository = ref.read(sportWaitlistRepositoryProvider);
      final compositionRepository = ref.read(
        matchCompositionRepositoryProvider,
      );
      final results = await Future.wait<Object?>([
        waitlistRepository.fetchMatchConvocations(matchId),
        compositionRepository.fetchAdminComposition(matchId),
        waitlistRepository.fetchReminderSummary(matchId),
      ]);
      final convocations = results[0] as MatchConvocations;
      final saved = results[1] as MatchComposition?;
      final reminders = results[2] as AvailabilityReminderSummary;
      final kickoffPassed = !DateTime.now().isBefore(convocations.kickoffAt);
      final finalization = kickoffPassed
          ? await ref
              .read(sportMatchFinalizationRepositoryProvider)
              .fetchAdminContext(matchId)
          : null;
      final postMatch = finalization != null &&
          finalization.isValidated &&
          (finalization.matchStatus == 'termine' ||
              finalization.matchStatus == 'archive');
      final actualPresent = {
        for (final participant in finalization?.participants ?? const [])
          if (participant.present) participant.participantId,
      };
      final goalkeeperIds = postMatch
          ? const <String>{}
          : await compositionRepository.fetchGoalkeeperSeasonPlayerIds([
              for (final player in convocations.players)
                if (player.seasonPlayerId.isNotEmpty) player.seasonPlayerId,
            ]);
      final composition = postMatch
          ? _normalizePostMatchComposition(finalization, saved)
          : _normalizeComposition(convocations, saved, goalkeeperIds);
      if (!mounted || _selectedMatchId != matchId) return;
      setState(() {
        _convocations = convocations;
        _composition = composition;
        _finalization = finalization;
        _postMatch = postMatch;
        _compositionExisted = saved != null;
        _actualPresent = actualPresent;
        _reminders = reminders;
        _desiredConvoked = postMatch
            ? actualPresent
            : {
                for (final player in convocations.players)
                  if ((player.isAvailable || player.isGuest) &&
                      player.isConvoked)
                    player.participantId,
              };
        _limitController.text = '${convocations.squadSizeLimit}';
        _effectifDirty = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Relance de disponibilité""",
)
replace_once(
    page,
    "  /// Rétablit sur le terrain les titulaires dont la position ne tombe sur aucun",
    "  MatchComposition _normalizePostMatchComposition(\n    SportMatchFinalization finalization,\n    MatchComposition? saved,\n  ) {\n    final baseline = MatchComposition.initialFromFinalization(\n      finalization: finalization,\n    );\n    if (saved == null) return baseline;\n    final savedById = {\n      for (final entry in saved.entries) entry.participantId: entry,\n    };\n    return _rescueOrphans(\n      saved.copyWith(\n        entries: [\n          for (final base in baseline.entries)\n            if (savedById[base.participantId] case final previous?)\n              MatchCompositionEntry(\n                participantId: base.participantId,\n                seasonPlayerId: base.seasonPlayerId,\n                guestPlayerId: base.guestPlayerId,\n                displayName: base.displayName,\n                isGuest: base.isGuest,\n                isGoalkeeper: base.isGoalkeeper,\n                zone: base.canBeSelected\n                    ? previous.zone == MatchCompositionZone.field\n                        ? MatchCompositionZone.field\n                        : MatchCompositionZone.bench\n                    : MatchCompositionZone.notSelected,\n                x: base.canBeSelected &&\n                        previous.zone == MatchCompositionZone.field\n                    ? previous.x\n                    : null,\n                y: base.canBeSelected &&\n                        previous.zone == MatchCompositionZone.field\n                    ? previous.y\n                    : null,\n                slotLabel: previous.slotLabel,\n                photoUrl: base.photoUrl ?? previous.photoUrl,\n                goals: base.goals,\n                isMotm: base.isMotm,\n                sortOrder: previous.sortOrder,\n                availabilityStatus: base.availabilityStatus,\n                convocationStatus: base.convocationStatus,\n                selectionStatus: base.canBeSelected\n                    ? previous.zone == MatchCompositionZone.field\n                        ? 'starter'\n                        : 'substitute'\n                    : 'not_selected',\n              )\n            else\n              base,\n        ],\n      ),\n    );\n  }\n\n  /// Rétablit sur le terrain les titulaires dont la position ne tombe sur aucun",
)
replace_once(
    page,
    "                slotLabel: previous.slotLabel,\n                sortOrder: previous.sortOrder,",
    "                slotLabel: previous.slotLabel,\n                photoUrl: previous.photoUrl ?? base.photoUrl,\n                goals: previous.goals,\n                isMotm: previous.isMotm,\n                sortOrder: previous.sortOrder,",
)
replace_once(
    page,
    "  bool get _locked {\n    final kickoff = _convocations?.kickoffAt;\n    return kickoff != null && !DateTime.now().isBefore(kickoff);\n  }",
    "  bool get _locked {\n    final kickoff = _convocations?.kickoffAt;\n    return kickoff != null && !DateTime.now().isBefore(kickoff);\n  }\n\n  bool get _compositionLocked =>\n      _busy || (_postMatch ? _compositionExisted : _locked);",
)
replace_once(
    page,
    "          (player) =>\n              (player.isAvailable || player.isGuest) &&\n              _desiredConvoked.contains(player.participantId),",
    "          (player) => _postMatch\n              ? _actualPresent.contains(player.participantId)\n              : (player.isAvailable || player.isGuest) &&\n                  _desiredConvoked.contains(player.participantId),",
)
replace_once(
    page,
    "      slotLabel: entry.slotLabel,\n      sortOrder: sortOrder ?? entry.sortOrder,",
    "      slotLabel: entry.slotLabel,\n      photoUrl: entry.photoUrl,\n      goals: entry.goals,\n      isMotm: entry.isMotm,\n      sortOrder: sortOrder ?? entry.sortOrder,",
)
# Only composition editing methods use the composition-specific lock.
for method in ("_applyFormation", "_dropOnSlot", "_moveToBench"):
    text = Path(page).read_text()
    start = text.index(f"  void {method}")
    end = text.find("\n  }", start) + 4
    block = text[start:end]
    block = block.replace("composition == null || _busy || _locked", "composition == null || _compositionLocked")
    Path(page).write_text(text[:start] + block + text[end:])

replace_regex(
    page,
    r"  Future<MatchComposition\?> _saveComposition\(\{required bool publish\}\) async \{.*?\n  \}\n\n  Future<void> _addGuest",
    """  Future<MatchComposition?> _saveComposition({required bool publish}) async {
    if (_composition == null || _compositionLocked) return null;
    setState(() => _busy = true);
    try {
      final repository = ref.read(matchCompositionRepositoryProvider);
      final ready = _compositionReadyToSave();
      late final MatchComposition result;
      if (_postMatch) {
        result = await repository.createPostMatchComposition(
          composition: ready,
          allowSquadSizeException: true,
          reason: 'Composition réelle publiée après finalisation du match',
        );
      } else {
        final saved = await repository.saveComposition(
          composition: ready,
          allowSquadSizeException: true,
          reason: publish
              ? 'Préparation de la publication'
              : 'Brouillon de composition',
        );
        if (publish) {
          await ref.read(sportWaitlistRepositoryProvider).publishMatch(
                matchId: ready.matchId,
                reason: 'Effectif confirmé avant publication de la composition',
              );
          result = await repository.publishComposition(
            matchId: ready.matchId,
            allowSquadSizeException: true,
            reason: 'Composition publiée depuis le match',
          );
        } else {
          result = saved;
        }
      }
      if (!mounted) return result;
      setState(() {
        _composition = result;
        if (_postMatch) _compositionExisted = true;
      });
      ref.invalidate(publishedMatchCompositionProvider(ready.matchId));
      _showMessage(publish ? 'Composition publiée.' : 'Brouillon enregistré.');
      return result;
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGuest""",
)
replace_once(
    page,
    "          title: 'Aucun match à venir',\n          message: 'Crée un match depuis l’onglet Matchs pour préparer '",
    "          title: 'Aucun match disponible',\n          message: 'Crée un match depuis l’onglet Matchs pour préparer '",
)
replace_once(
    page,
    "                const Text(\n                  'Choisis un dispositif, puis glisse les convoqués sur les '\n                  'postes affichés.',\n                ),",
    "                Text(\n                  _postMatch\n                      ? 'Choisis un dispositif, puis glisse les joueurs réellement présents sur les postes affichés.'\n                      : 'Choisis un dispositif, puis glisse les convoqués sur les postes affichés.',\n                ),",
)
replace_once(
    page,
    "                  onChanged: (_busy || _locked) ? null : _applyFormation,",
    "                  onChanged: _compositionLocked ? null : _applyFormation,",
)
replace_once(page, "            editable: !_busy && !_locked,", "            editable: !_compositionLocked,")
replace_once(
    page,
    "          onWillAcceptWithDetails: (details) => !_busy && !_locked,",
    "          onWillAcceptWithDetails: (details) => !_compositionLocked,",
)
replace_once(page, "                            draggable: !_busy && !_locked,", "                            draggable: !_compositionLocked,")
replace_once(
    page,
    "          onPressed:\n              _busy || _locked ? null : () => _saveComposition(publish: true),",
    "          onPressed: _compositionLocked\n              ? null\n              : () => _saveComposition(publish: true),",
)
replace_once(
    page,
    "          label: Text(composition.isPublished ? 'Mettre à jour' : 'Publier'),",
    "          label: Text(\n            _postMatch && _compositionExisted\n                ? 'Composition publiée'\n                : composition.isPublished\n                    ? 'Mettre à jour'\n                    : 'Publier',\n          ),",
)
replace_once(
    page,
    "        if (_locked)\n          const Padding(\n            padding: EdgeInsets.only(top: 10),\n            child: Text('Composition verrouillée au coup d’envoi.'),\n          ),",
    "        if (_postMatch && _compositionExisted)\n          const Padding(\n            padding: EdgeInsets.only(top: 10),\n            child: Text(\n              'Composition verrouillée : une composition existe déjà pour ce match.',\n            ),\n          )\n        else if (_locked && !_postMatch)\n          const Padding(\n            padding: EdgeInsets.only(top: 10),\n            child: Text(\n              'Finalise d’abord le match pour utiliser les joueurs réellement présents.',\n            ),\n          ),",
)

# Add access to the same editor from a completed match.
match_details = "lib/features/matches/presentation/match_details_page.dart"
replace_once(
    match_details,
    "                  FilledButton.icon(\n                    onPressed: () => context.push('/matches/$matchId/finalize'),",
    "                  OutlinedButton.icon(\n                    onPressed: () => context.push(\n                      '/matches/$matchId/composition?step=composition',\n                    ),\n                    icon: const Icon(Icons.dashboard_customize_outlined),\n                    label: const Text('Gérer la composition'),\n                  ),\n                  const SizedBox(height: 10),\n                  FilledButton.icon(\n                    onPressed: () => context.push('/matches/$matchId/finalize'),",
)

# Focused regression tests for metadata retention and finalization initialization.
Path("test/match_composition_metadata_test.dart").write_text(
    """import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moving an entry preserves display metadata', () {
    const entry = MatchCompositionEntry(
      participantId: 'participant',
      seasonPlayerId: 'player',
      displayName: 'Samih',
      isGoalkeeper: false,
      zone: MatchCompositionZone.bench,
      photoUrl: 'https://example.test/photo.jpg',
      goals: 2,
      isMotm: true,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'substitute',
    );

    final moved = entry.moveTo(
      MatchCompositionZone.field,
      x: .5,
      y: .8,
    );

    expect(moved.photoUrl, entry.photoUrl);
    expect(moved.goals, 2);
    expect(moved.isMotm, isTrue);
  });

  test('post-match initialization selects only actual present players', () {
    final finalization = SportMatchFinalization(
      matchId: 'match',
      opponentName: 'Adversaire',
      isHome: true,
      kickoffAt: DateTime(2026),
      matchStatus: 'termine',
      isValidated: true,
      version: 1,
      scoreAsGrinta: 2,
      scoreAdverse: 1,
      compositionVersion: 0,
      presenceState: 'confirmed',
      voteState: 'draft',
      participants: const [
        SportFinalParticipant(
          participantId: 'present',
          seasonPlayerId: 'player-present',
          displayName: 'Présent',
          isGuest: false,
          isGoalkeeper: true,
          plannedZone: 'available',
          present: true,
          selectionStatus: SportFinalSelectionStatus.substitute,
          goals: 1,
          cleanSheet: false,
          photoUrl: 'https://example.test/present.jpg',
          isMotm: true,
        ),
        SportFinalParticipant(
          participantId: 'absent',
          seasonPlayerId: 'player-absent',
          displayName: 'Absent',
          isGuest: false,
          isGoalkeeper: false,
          plannedZone: 'field',
          present: false,
          selectionStatus: SportFinalSelectionStatus.notSelected,
          goals: 0,
          cleanSheet: false,
        ),
      ],
    );

    final composition = MatchComposition.initialFromFinalization(
      finalization: finalization,
    );

    final present = composition.entries.singleWhere(
      (entry) => entry.participantId == 'present',
    );
    final absent = composition.entries.singleWhere(
      (entry) => entry.participantId == 'absent',
    );
    expect(present.zone, MatchCompositionZone.bench);
    expect(present.photoUrl, isNotNull);
    expect(present.goals, 1);
    expect(present.isMotm, isTrue);
    expect(absent.zone, MatchCompositionZone.notSelected);
  });
}
"""
)

# Add the database completion migration. It introduces an atomic one-shot RPC,
# enriches the existing finalization snapshot, and guards legacy composition
# writes on finished matches.
Path("supabase/migrations/20260725220000_complete_postmatch_composition_once.sql").write_text(
    r"""-- Complete the post-match composition editor with one atomic creation.
-- The existing allow_postmatch_composition_editor migration is intentionally
-- reused and not recreated.

create or replace function private.guard_finished_match_composition_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_status text;
begin
  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;
  select match.status::text into v_status
  from public.matches match
  where match.id = v_match_id;

  if v_status in ('termine', 'archive')
     and coalesce(
       current_setting('as_grinta.allow_postmatch_composition_write', true),
       'off'
     ) <> 'on' then
    raise exception 'Finished match compositions are immutable'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_finished_match_composition_write()
from public, anon, authenticated;

drop trigger if exists guard_finished_match_composition_write
  on public.match_compositions;
create trigger guard_finished_match_composition_write
before insert or update or delete on public.match_compositions
for each row execute function private.guard_finished_match_composition_write();

drop trigger if exists guard_finished_match_composition_entry_write
  on public.match_composition_entries;
create trigger guard_finished_match_composition_entry_write
before insert or update or delete on public.match_composition_entries
for each row execute function private.guard_finished_match_composition_write();

drop trigger if exists guard_finished_match_composition_publication_write
  on public.match_composition_publications;
create trigger guard_finished_match_composition_publication_write
before insert or update or delete on public.match_composition_publications
for each row execute function private.guard_finished_match_composition_write();

create or replace function private.match_sport_finalization_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  with latest_publication as (
    select publication.version, publication.snapshot
    from public.match_composition_publications publication
    where publication.match_id = p_match_id
    order by publication.version desc
    limit 1
  ), planned_entries as (
    select
      (entry ->> 'participant_id')::uuid as participant_id,
      entry ->> 'zone' as planned_zone
    from latest_publication publication,
      lateral jsonb_array_elements(
        coalesce(publication.snapshot -> 'entries', '[]'::jsonb)
      ) entry
  )
  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'is_home', match.location = 'domicile',
    'kickoff_at', match.kickoff_at,
    'match_status', match.status,
    'is_validated', finalization.match_id is not null,
    'version', coalesce(finalization.version, 0),
    'score_as_grinta', coalesce(finalization.score_as_grinta, match.score_as_grinta, 0),
    'score_adverse', coalesce(finalization.score_adverse, match.score_adverse, 0),
    'composition_version', coalesce(finalization.composition_version, workflow.composition_version, 0),
    'presence_state', workflow.presence_state,
    'vote_state', workflow.vote_state,
    'validated_at', finalization.validated_at,
    'corrected_at', finalization.corrected_at,
    'participants', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'is_guest', participant.guest_player_id is not null,
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else coalesce(
            nullif(btrim(profile.surnom), ''),
            nullif(btrim(player.first_name), ''),
            btrim(concat_ws(' ', player.first_name, player.last_name))
          )
        end,
        'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'planned_zone', coalesce(planned.planned_zone, case participant.selection_status
          when 'starter' then 'field'
          when 'substitute' then 'bench'
          when 'not_selected' then 'not_selected'
          else 'available'
        end),
        'present', case
          when finalization.match_id is not null then participant.final_presence_status = 'present'
          else coalesce(planned.planned_zone in ('field', 'bench'), false)
        end,
        'final_presence_status', participant.final_presence_status,
        'final_selection_status', case
          when finalization.match_id is not null then participant.final_selection_status
          when planned.planned_zone = 'field' then 'starter'::public.sport_selection_status
          when planned.planned_zone = 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end,
        'goals', participant.final_goals,
        'clean_sheet', participant.final_clean_sheet,
        'is_motm', exists (
          select 1
          from public.match_sport_motm_results result
          where result.match_id = p_match_id
            and result.participant_id = participant.id
            and result.is_winner
            and result.finalization_version = (
              select max(latest.finalization_version)
              from public.match_sport_motm_results latest
              where latest.match_id = p_match_id
            )
        )
      ) order by
        case coalesce(planned.planned_zone, '')
          when 'field' then 1
          when 'bench' then 2
          else 3
        end,
        lower(coalesce(profile.surnom, player.first_name, guest.first_name)),
        participant.id
    ) filter (
      where participant.id is not null
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    ), '[]'::jsonb)
  ) into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  left join public.match_sport_participants participant on participant.match_id = match.id
  left join public.season_players player on player.id = participant.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join planned_entries planned on planned.participant_id = participant.id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id, finalization.match_id;

  return v_result;
end;
$function$;

create or replace function private.create_postmatch_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_formation text := nullif(btrim(p_formation_code), '');
  v_match_status text;
  v_kickoff_at timestamptz;
  v_squad_limit integer;
  v_finalized boolean;
  v_expected_count integer;
  v_input_count integer;
  v_field_count integer;
  v_selected_count integer;
  v_present_count integer;
  v_invalid_count integer;
  v_exception_used boolean;
  v_snapshot jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Composition entries must be a JSON array' using errcode = '22023';
  end if;
  if v_formation is not null and char_length(v_formation) > 32 then
    raise exception 'Formation code cannot exceed 32 characters' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select
    match.status::text,
    match.kickoff_at,
    workflow.squad_size_limit,
    finalization.match_id is not null
  into v_match_status, v_kickoff_at, v_squad_limit, v_finalized
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('termine', 'archive') or now() < v_kickoff_at then
    raise exception 'Post-match composition requires a finished match'
      using errcode = '22023';
  end if;
  if not v_finalized then
    raise exception 'The match must be finalized before creating its composition'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from public.match_compositions composition
    where composition.match_id = p_match_id
  ) or exists (
    select 1 from public.match_composition_publications publication
    where publication.match_id = p_match_id
  ) then
    raise exception 'A composition already exists for this match'
      using errcode = '55000';
  end if;

  create temporary table if not exists pg_temp.postmatch_composition_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.postmatch_composition_input;

  begin
    insert into pg_temp.postmatch_composition_input(
      participant_id, zone, x, y, slot_label, sort_order
    )
    select
      (item ->> 'participant_id')::uuid,
      (item ->> 'zone')::public.sport_composition_zone,
      case when item ->> 'x' is null then null else (item ->> 'x')::numeric end,
      case when item ->> 'y' is null then null else (item ->> 'y')::numeric end,
      nullif(btrim(item ->> 'slot_label'), ''),
      greatest(0, coalesce((item ->> 'sort_order')::integer, 0))
    from jsonb_array_elements(p_entries) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once in a composition'
        using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid composition entry' using errcode = '22023';
  end;

  select count(*) into v_input_count
  from pg_temp.postmatch_composition_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (
      participant.is_eligible
      or participant.final_presence_status <> 'pending'
    );
  if v_input_count <> v_expected_count then
    raise exception 'Every finalized participant must appear exactly once'
      using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from pg_temp.postmatch_composition_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and (
     participant.is_eligible
     or participant.final_presence_status <> 'pending'
   )
  where participant.id is null
     or input.zone = 'available'
     or (
       input.zone = 'field'
       and (
         input.x is null or input.y is null
         or input.x < 0 or input.x > 1
         or input.y < 0 or input.y > 1
       )
     )
     or (input.zone <> 'field' and (input.x is not null or input.y is not null))
     or (
       participant.final_presence_status = 'present'
       and input.zone not in ('field', 'bench')
     )
     or (
       participant.final_presence_status <> 'present'
       and input.zone <> 'not_selected'
     );
  if v_invalid_count > 0 then
    raise exception 'Composition must contain only actual present players'
      using errcode = '22023';
  end if;

  select
    count(*) filter (where input.zone = 'field'),
    count(*) filter (where input.zone in ('field', 'bench'))
  into v_field_count, v_selected_count
  from pg_temp.postmatch_composition_input input;
  select count(*) into v_present_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.final_presence_status = 'present';

  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters'
      using errcode = '22023';
  end if;
  if v_selected_count <> v_present_count then
    raise exception 'Every actual present player must be on the field or bench'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
     and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  perform set_config(
    'as_grinta.allow_postmatch_composition_write',
    'on',
    true
  );

  insert into public.match_compositions(
    match_id, formation_code, status, version, has_unpublished_changes,
    squad_size_exception_approved, published_at, published_by,
    last_modified_at, last_modified_by, closed_at
  ) values (
    p_match_id, v_formation, 'published', 1, false,
    v_exception_used, now(), v_actor, now(), v_actor, now()
  );

  insert into public.match_composition_entries(
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.postmatch_composition_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      final_selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.postmatch_composition_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = 'published',
      composition_version = 1,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  update public.match_sport_finalizations finalization
  set composition_version = 1,
      updated_at = now()
  where finalization.match_id = p_match_id;

  v_snapshot := private.composition_snapshot(p_match_id)
    || jsonb_build_object(
      'published_at', now(),
      'publication_kind', 'postmatch'
    );

  insert into public.match_composition_publications(
    match_id, version, formation_code, snapshot,
    publication_kind, published_by
  ) values (
    p_match_id, 1, v_formation, v_snapshot, 'postmatch', v_actor
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'publish_postmatch_composition',
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', 1,
      'publication_kind', 'postmatch',
      'field_count', v_field_count,
      'bench_count', v_selected_count - v_field_count,
      'present_count', v_present_count,
      'match_status', v_match_status,
      'exception_used', v_exception_used
    )
  );

  return private.get_published_match_composition(p_match_id);
end;
$function$;

revoke all on function private.create_postmatch_composition(
  uuid, text, jsonb, boolean, text
) from public, anon, authenticated;

create or replace function public.admin_create_postmatch_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb
language sql
set search_path = ''
as $function$
  select private.create_postmatch_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason
  );
$function$;

revoke all on function public.admin_create_postmatch_composition(
  uuid, text, jsonb, boolean, text
) from public, anon;
grant execute on function public.admin_create_postmatch_composition(
  uuid, text, jsonb, boolean, text
) to authenticated;
"""
)
