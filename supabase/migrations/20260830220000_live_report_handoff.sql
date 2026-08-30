begin;

-- Projection en lecture seule des buts du Live vers le brouillon du compte
-- rendu. Les faits durables restent écrits uniquement lors de la validation.
create or replace function private.match_live_report_goal_actions_json(
  p_match_id uuid
)
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', null,
        'ordinal', projected.ordinal,
        'minute', projected.minute,
        'team_side', projected.team_side,
        'scorer_participant_id', projected.scorer_participant_id,
        'scorer_name', projected.scorer_name,
        'assist_participant_id', projected.assist_participant_id,
        'assist_kind', projected.assist_kind,
        'assist_name', projected.assist_name,
        'is_own_goal', projected.is_own_goal,
        'source', 'live',
        'source_live_event_id', projected.source_live_event_id
      ) order by projected.ordinal
    ),
    '[]'::jsonb
  )
  from (
    select
      (row_number() over (
        order by event.half, event.minute, event.created_at, event.id
      ) - 1)::integer as ordinal,
      least(greatest(event.minute, 0), 90)::smallint as minute,
      case when event.event_type = 'goal_them'
        then 'opponent' else 'as_grinta' end as team_side,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false) then null
        else event.scorer_participant_id
      end as scorer_participant_id,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false) then null
        when scorer_guest.id is not null then
          btrim(scorer_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(scorer_profile.surnom), ''),
          nullif(btrim(scorer_profile.first_name), ''),
          nullif(btrim(scorer_player.first_name), '')
        )
      end as scorer_name,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false)
          or event.scorer_participant_id is null then null
        else nullif(to_jsonb(event) ->> 'assist_participant_id', '')::uuid
      end as assist_participant_id,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false) then 'none'
        when event.scorer_participant_id is null then 'unknown'
        when nullif(to_jsonb(event) ->> 'assist_participant_id', '') is not null then 'player'
        else 'unknown'
      end as assist_kind,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false)
          or event.scorer_participant_id is null then null
        when assist_guest.id is not null then
          btrim(assist_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(assist_profile.surnom), ''),
          nullif(btrim(assist_profile.first_name), ''),
          nullif(btrim(assist_player.first_name), '')
        )
      end as assist_name,
      event.event_type = 'goal_us'
        and coalesce(event.is_opponent_own_goal, false) as is_own_goal,
      event.id as source_live_event_id
    from public.match_live_events event
    left join public.match_sport_participants scorer_p
      on scorer_p.id = event.scorer_participant_id
    left join public.season_players scorer_player
      on scorer_player.id = scorer_p.season_player_id
    left join public.profiles scorer_profile
      on scorer_profile.id = scorer_player.profile_id
    left join public.guest_players scorer_guest
      on scorer_guest.id = scorer_p.guest_player_id
    left join public.match_sport_participants assist_p
      on assist_p.id = nullif(to_jsonb(event) ->> 'assist_participant_id', '')::uuid
    left join public.season_players assist_player
      on assist_player.id = assist_p.season_player_id
    left join public.profiles assist_profile
      on assist_profile.id = assist_player.profile_id
    left join public.guest_players assist_guest
      on assist_guest.id = assist_p.guest_player_id
    where event.match_id = p_match_id
      and event.event_type in ('goal_us', 'goal_them')
  ) projected;
$function$;

alter function private.match_live_report_goal_actions_json(uuid) owner to postgres;
revoke all on function private.match_live_report_goal_actions_json(uuid)
  from public, authenticated;

-- `private.get_match_sport_report` reste inchangée : elle continue de porter
-- toutes les règles d'autorisation, d'effectif et de correction. Le point
-- d'entrée public enrichit seulement le cas transitoire Live fini/non exporté.
create or replace function public.admin_get_match_sport_report(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_report jsonb;
  v_live_state public.match_live_state;
  v_live_exported boolean;
  v_score_as_grinta integer;
  v_score_adverse integer;
begin
  v_report := private.get_match_sport_report(p_match_id);

  if not coalesce((v_report ->> 'is_validated')::boolean, false) then
    select
      session.state,
      session.exported,
      session.score_as_grinta,
      session.score_adverse
    into
      v_live_state,
      v_live_exported,
      v_score_as_grinta,
      v_score_adverse
    from public.match_live_sessions session
    where session.match_id = p_match_id;

    if v_live_state = 'finished'
       and not coalesce(v_live_exported, false) then
      v_report := v_report || jsonb_build_object(
        'score_as_grinta', coalesce(v_score_as_grinta, 0),
        'score_adverse', coalesce(v_score_adverse, 0),
        'goal_actions', private.match_live_report_goal_actions_json(p_match_id)
      );
    end if;
  end if;

  return v_report;
end;
$function$;

alter function public.admin_get_match_sport_report(uuid) owner to postgres;
revoke all on function public.admin_get_match_sport_report(uuid) from public, anon;
grant execute on function public.admin_get_match_sport_report(uuid)
  to authenticated, service_role;

commit;
