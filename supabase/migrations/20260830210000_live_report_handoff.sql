begin;

-- Un Live terminé mais pas encore validé possède déjà la vérité du score et
-- des buts dans match_live_sessions / match_live_events. Le compte rendu ne
-- doit pas retomber sur le score du match (encore vide) ni sur la table
-- durable match_sport_goal_actions (remplie seulement à la validation).
--
-- Cette projection est volontairement en lecture seule : le journal Live reste
-- intact jusqu'au clic sur « Valider le compte rendu », moment où
-- admin_submit_match_sport_report persiste les faits dans le modèle durable.
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
      case
        when event.event_type = 'goal_them' then 'opponent'
        else 'as_grinta'
      end as team_side,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false)
          then null
        else event.scorer_participant_id
      end as scorer_participant_id,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false)
          then null
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
          or event.scorer_participant_id is null
          then null
        else event.assist_participant_id
      end as assist_participant_id,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false)
          then 'none'
        when event.scorer_participant_id is null then 'unknown'
        when event.assist_participant_id is not null then 'player'
        else 'unknown'
      end as assist_kind,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false)
          or event.scorer_participant_id is null
          then null
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
      on assist_p.id = event.assist_participant_id
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
revoke all on function private.match_live_report_goal_actions_json(uuid) from public;
revoke all on function private.match_live_report_goal_actions_json(uuid) from authenticated;

create or replace function private.get_match_sport_report(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_base jsonb;
  v_live_state text;
  v_live_exported boolean;
  v_live_finished boolean;
  v_live_score_as_grinta integer;
  v_live_score_adverse integer;
  v_status text;
  v_closes_at timestamptz;
  v_is_validated boolean;
  v_season_id uuid;
  v_roster jsonb;
  v_guests jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() and not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select match.status::text, match.season_id
  into v_status, v_season_id
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  v_base := private.match_sport_finalization_snapshot(p_match_id);
  if v_base is null then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;

  v_is_validated := coalesce((v_base ->> 'is_validated')::boolean, false);
  v_closes_at := private.match_postgame_correction_closes_at(p_match_id);

  select
    session.state::text,
    session.exported,
    session.state = 'finished',
    session.score_as_grinta,
    session.score_adverse
  into
    v_live_state,
    v_live_exported,
    v_live_finished,
    v_live_score_as_grinta,
    v_live_score_adverse
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  -- Entre « Fin du match » et la première validation, le Live est la source
  -- de vérité du brouillon. Aucun write n'a lieu ici : un refresh, un crash ou
  -- un autre appareil reconstruit exactement le même compte rendu.
  if not v_is_validated
     and coalesce(v_live_finished, false)
     and not coalesce(v_live_exported, false) then
    v_base := v_base || jsonb_build_object(
      'score_as_grinta', coalesce(v_live_score_as_grinta, 0),
      'score_adverse', coalesce(v_live_score_adverse, 0),
      'goal_actions', private.match_live_report_goal_actions_json(p_match_id)
    );
  end if;

  -- Joueurs qu'on peut encore ajouter à l'effectif du compte rendu : ceux du
  -- roster sans participation ouverte, et les invités réutilisables.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'season_player_id', candidate.season_player_id,
      'display_name', candidate.display_name,
      'photo_url', candidate.photo_url,
      'is_goalkeeper', candidate.is_goalkeeper,
      'is_guest', false
    ) order by lower(candidate.display_name), candidate.season_player_id
  ), '[]'::jsonb)
  into v_roster
  from (
    select
      player.id as season_player_id,
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        btrim(concat_ws(' ', player.first_name, player.last_name)),
        'Joueur'
      ) as display_name,
      coalesce(profile.photo_url, player.photo_url) as photo_url,
      player.is_goalkeeper
    from public.season_players player
    left join public.profiles profile on profile.id = player.profile_id
    where player.season_id = v_season_id
      and player.is_active
      and (player.profile_id is null or profile.status = 'active')
      and not exists (
        select 1
        from public.match_sport_participants participant
        where participant.match_id = p_match_id
          and participant.season_player_id = player.id
          and (
            participant.is_eligible
            or participant.final_presence_status <> 'pending'
          )
      )
  ) candidate;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'guest_player_id', guest.id,
      'display_name', btrim(concat_ws(' ', guest.first_name, guest.last_name)),
      'photo_url', guest.photo_url,
      'is_goalkeeper', guest.is_goalkeeper,
      'is_guest', true
    ) order by lower(guest.first_name), guest.id
  ), '[]'::jsonb)
  into v_guests
  from public.guest_players guest
  where guest.is_reusable
    and guest.archived_at is null
    and not exists (
      select 1
      from public.match_sport_participants participant
      where participant.match_id = p_match_id
        and participant.guest_player_id = guest.id
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    );

  return v_base || jsonb_build_object(
    'lineup', private.match_sport_report_lineup(p_match_id),
    'is_correction', v_is_validated,
    'correction_closes_at', v_closes_at,
    'is_editable', v_status <> 'archive'
      and (
        not v_is_validated
        or v_closes_at is null
        or now() < v_closes_at
      ),
    'live_state', v_live_state,
    'live_exported', coalesce(v_live_exported, false),
    'live_finished', coalesce(v_live_finished, false),
    'add_player_options', jsonb_build_object(
      'roster', v_roster,
      'guests', v_guests
    )
  );
end;
$function$;

commit;
