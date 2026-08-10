-- Ajoute is_home au snapshot de finalisation pour afficher le score au format
-- domicile au-dessus / extérieur en dessous sur l'écran de validation.
CREATE OR REPLACE FUNCTION private.match_sport_finalization_snapshot(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          else btrim(concat_ws(' ', player.first_name, player.last_name))
        end,
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
        'clean_sheet', participant.final_clean_sheet
      ) order by
        case coalesce(planned.planned_zone, '')
          when 'field' then 1
          when 'bench' then 2
          else 3
        end,
        lower(coalesce(player.first_name, guest.first_name)),
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
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join planned_entries planned on planned.participant_id = participant.id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id, finalization.match_id;

  return v_result;
end;
$function$;
