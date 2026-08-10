begin;

create or replace function private.match_features_open_at(
  p_kickoff_at timestamptz
)
returns timestamptz
language sql
stable
strict
set search_path to ''
as $function$
  select (
    (
      (p_kickoff_at at time zone 'Europe/Paris')::date - 6
    ) + time '12:00'
  ) at time zone 'Europe/Paris';
$function$;

comment on function private.match_features_open_at(timestamptz) is
  'Noon Europe/Paris on the sixth calendar day before kickoff.';

revoke all on function private.match_features_open_at(timestamptz)
  from public, anon, authenticated;

create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_kickoff timestamptz;
  v_match_status text;
  v_closed_at timestamptz;
begin
  if (select auth.uid()) is not null and pg_trigger_depth() <= 1 then
    if tg_op = 'UPDATE' and new.match_id is distinct from old.match_id then
      raise exception 'Le match d’un pronostic ne peut pas être modifié.'
        using errcode = '22023';
    end if;
    new.profile_id := (select auth.uid());
  end if;

  if new.is_filled then
    select m.kickoff_at, m.status, m.predictions_closed_at
    into v_kickoff, v_match_status, v_closed_at
    from public.matches m
    where m.id = new.match_id;

    if v_kickoff is null
       or v_match_status <> 'a_venir'
       or now() < private.match_features_open_at(v_kickoff)
       or now() >= v_kickoff - interval '5 minutes'
       or (v_closed_at is not null and now() >= v_closed_at) then
      raise exception 'Pronostic fermé' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_match public.matches%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Utilisateur non authentifié.' using errcode = '42501';
  end if;
  if not private.is_active_profile() then
    raise exception 'Compte inactif.' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match requis.' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta not between 0 and 99
     or p_score_adverse not between 0 and 99 then
    raise exception 'Les scores doivent être compris entre 0 et 99.'
      using errcode = '22023';
  end if;

  select *
  into v_match
  from public.matches
  where id = p_match_id
  for share;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_match.kickoff_at is null
     or v_match.status <> 'a_venir'
     or now() < private.match_features_open_at(v_match.kickoff_at)
     or now() >= v_match.kickoff_at - interval '5 minutes'
     or (
       v_match.predictions_closed_at is not null
       and now() >= v_match.predictions_closed_at
     ) then
    raise exception 'Ce match n’est pas ouvert aux pronostics.'
      using errcode = '22023';
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled,
    updated_at
  ) values (
    p_match_id,
    v_actor_id,
    p_score_as_grinta,
    p_score_adverse,
    true,
    now()
  )
  on conflict (match_id, profile_id) do update
  set predicted_score_as_grinta = excluded.predicted_score_as_grinta,
      predicted_score_adverse = excluded.predicted_score_adverse,
      is_filled = true,
      updated_at = now();

  return true;
end;
$function$;

create or replace function private.sync_match_sport_workflow(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_kickoff_at timestamptz;
  v_match_status text;
  v_config jsonb;
  v_default_squad_size integer := 14;
  v_opens_at timestamptz;
  v_computed_state public.sport_availability_state;
  v_saved_state public.sport_availability_state;
  v_opened_at timestamptz;
  v_eligible_count integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.season_id, match.kickoff_at, match.status
  into v_season_id, v_kickoff_at, v_match_status
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' then
    raise exception 'Only upcoming matches can be synchronized' using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  select flag.config into v_config
  from private.app_feature_flags flag
  where flag.key = 'sports_management';

  if coalesce(v_config ->> 'usual_squad_size', '') ~ '^[0-9]+$' then
    v_default_squad_size := greatest(
      1,
      least(30, (v_config ->> 'usual_squad_size')::integer)
    );
  end if;

  v_opens_at := private.match_features_open_at(v_kickoff_at);
  v_computed_state := case
    when now() >= v_kickoff_at then 'closed'::public.sport_availability_state
    when now() >= v_opens_at then 'open'::public.sport_availability_state
    else 'pending'::public.sport_availability_state
  end;

  insert into public.match_sport_workflows as workflow (
    match_id,
    availability_state,
    availability_opens_at,
    availability_opened_at,
    squad_size_limit,
    created_by,
    updated_by
  ) values (
    p_match_id,
    v_computed_state,
    v_opens_at,
    case when v_computed_state = 'open' then now() else null end,
    v_default_squad_size,
    v_actor,
    v_actor
  )
  on conflict (match_id) do update
  set availability_opens_at = excluded.availability_opens_at,
      availability_state = v_computed_state,
      availability_opened_at = case
        when v_computed_state = 'open'
          then coalesce(workflow.availability_opened_at, now())
        else null
      end,
      updated_by = v_actor,
      updated_at = now()
  returning availability_state, availability_opened_at
  into v_saved_state, v_opened_at;

  update public.match_sport_participants participant
  set is_eligible = false,
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.season_player_id is not null
    and participant.is_eligible
    and not exists (
      select 1
      from public.season_players player
      where player.id = participant.season_player_id
        and player.season_id = v_season_id
        and player.is_active
        and not player.is_coach
    );

  insert into public.match_sport_participants as participant (
    match_id,
    season_player_id,
    is_eligible
  )
  select p_match_id, player.id, not player.is_coach
  from public.season_players player
  where player.season_id = v_season_id
    and player.is_active
  on conflict (match_id, season_player_id) do update
  set is_eligible = excluded.is_eligible,
      updated_at = case
        when participant.is_eligible = excluded.is_eligible
          then participant.updated_at
        else now()
      end;

  select count(*)::integer into v_eligible_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible;

  return jsonb_build_object(
    'match_id', p_match_id,
    'availability_state', v_saved_state,
    'availability_opens_at', v_opens_at,
    'availability_opened_at', v_opened_at,
    'kickoff_at', v_kickoff_at,
    'squad_size_limit', (
      select workflow.squad_size_limit
      from public.match_sport_workflows workflow
      where workflow.match_id = p_match_id
    ),
    'eligible_participant_count', v_eligible_count
  );
end;
$function$;

update public.match_sport_workflows workflow
set availability_opens_at = private.match_features_open_at(match.kickoff_at),
    availability_state = case
      when match.status <> 'a_venir' or now() >= match.kickoff_at
        then 'closed'::public.sport_availability_state
      when now() >= private.match_features_open_at(match.kickoff_at)
        then 'open'::public.sport_availability_state
      else 'pending'::public.sport_availability_state
    end,
    availability_opened_at = case
      when match.status = 'a_venir'
       and now() >= private.match_features_open_at(match.kickoff_at)
       and now() < match.kickoff_at
        then coalesce(workflow.availability_opened_at, now())
      else null
    end,
    updated_at = now()
from public.matches match
where match.id = workflow.match_id
  and match.kickoff_at is not null;

create or replace function public.internal_match_weather_candidates(
  p_match_id uuid default null,
  p_now timestamptz default now()
)
returns table (
  match_id uuid,
  kickoff_at timestamptz,
  planned_duration_minutes integer,
  resolved_address text,
  cached_latitude double precision,
  cached_longitude double precision,
  cached_geocoded_address text
)
language sql
stable
security definer
set search_path to ''
as $function$
  select
    match.id,
    match.kickoff_at,
    match.planned_duration_minutes,
    address.resolved_address,
    weather.latitude,
    weather.longitude,
    weather.geocoded_address
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  left join public.club_settings club on club.id
  left join public.match_weather weather on weather.match_id = match.id
  cross join lateral (
    select coalesce(
      nullif(btrim(match.address), ''),
      case
        when match.location = 'domicile'
          then nullif(btrim(club.home_address), '')
        else nullif(btrim(opponent.address), '')
      end
    ) as resolved_address
  ) address
  where match.status = 'a_venir'
    and match.kickoff_at is not null
    and match.kickoff_at > p_now
    and private.match_features_open_at(match.kickoff_at) <= p_now
    and address.resolved_address is not null
    and (p_match_id is null or match.id = p_match_id)
    and (
      weather.match_id is null
      or weather.forecast_for is distinct from match.kickoff_at
      or weather.geocoded_address is distinct from address.resolved_address
      or weather.fetched_at is null
      or weather.fetched_at <= p_now - private.match_weather_refresh_interval(
        match.kickoff_at,
        p_now
      )
    )
  order by match.kickoff_at;
$function$;

create or replace function private.open_match_live_workspace(
  p_match_id uuid,
  p_planned_duration_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_match_status text;
  v_kickoff_at timestamptz;
  v_default_duration integer;
  v_existing_state public.match_live_state;
  v_publication_snapshot jsonb;
  v_formation text;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select match.status, match.kickoff_at, match.planned_duration_minutes
  into v_match_status, v_kickoff_at, v_default_duration
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' then
    raise exception 'Live tracking is only available for upcoming matches'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  select session.state into v_existing_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if found and v_existing_state <> 'not_started' then
    return private.match_live_snapshot(p_match_id);
  end if;

  if now() < v_kickoff_at - interval '15 minutes' then
    raise exception 'Le Live ouvre 15 minutes avant le coup d’envoi.'
      using errcode = '22023';
  end if;

  if found then
    update public.match_live_sessions
    set planned_duration_minutes = greatest(
          1,
          least(
            200,
            coalesce(p_planned_duration_minutes, planned_duration_minutes)
          )
        ),
        updated_by = v_actor,
        updated_at = now()
    where match_id = p_match_id;

    return private.match_live_snapshot(p_match_id);
  end if;

  select publication.snapshot, publication.formation_code
  into v_publication_snapshot, v_formation
  from public.match_composition_publications publication
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_publication_snapshot is null then
    raise exception 'No published composition to start from' using errcode = '22023';
  end if;

  insert into public.match_live_sessions (
    match_id,
    state,
    planned_duration_minutes,
    updated_by
  ) values (
    p_match_id,
    'not_started',
    greatest(
      1,
      least(200, coalesce(p_planned_duration_minutes, v_default_duration))
    ),
    v_actor
  );

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id,
    participant_id,
    zone,
    x,
    y,
    slot_label,
    sort_order
  )
  select
    p_match_id,
    (entry ->> 'participant_id')::uuid,
    (entry ->> 'zone')::public.sport_composition_zone,
    case when entry ->> 'x' is null then null else (entry ->> 'x')::numeric end,
    case when entry ->> 'y' is null then null else (entry ->> 'y')::numeric end,
    entry ->> 'slot_label',
    coalesce((entry ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(v_publication_snapshot -> 'entries') entry
  where (entry ->> 'zone') in ('field', 'bench', 'not_selected');

  update public.match_compositions
  set formation_code = v_formation,
      last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.confirm_start_match_live(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_kickoff_at timestamptz;
  v_field_count integer;
  v_composition_version integer;
  v_snapshot_map jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, match.kickoff_at
  into v_state, v_kickoff_at
  from public.match_live_sessions session
  join public.matches match on match.id = session.match_id
  where session.match_id = p_match_id
  for update of session;

  if not found then
    raise exception 'Open the live workspace before starting the match'
      using errcode = '22023';
  end if;
  if v_state <> 'not_started' then
    raise exception 'The match has already been started' using errcode = '22023';
  end if;
  if v_kickoff_at is null
     or now() < v_kickoff_at - interval '15 minutes' then
    raise exception 'Le Live ouvre 15 minutes avant le coup d’envoi.'
      using errcode = '22023';
  end if;

  select count(*) filter (where zone = 'field') into v_field_count
  from public.match_composition_entries
  where match_id = p_match_id;
  if v_field_count > 11 then
    raise exception 'A lineup cannot contain more than 11 starters'
      using errcode = '22023';
  end if;

  select composition.version into v_composition_version
  from public.match_compositions composition
  where composition.match_id = p_match_id;

  select coalesce(
    jsonb_object_agg(entry.participant_id::text, entry.zone),
    '{}'::jsonb
  )
  into v_snapshot_map
  from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.zone in ('field', 'bench');

  update public.match_live_sessions
  set state = 'running',
      started_at = now(),
      running_since = now(),
      elapsed_seconds = 0,
      half = 1,
      starting_composition_version = v_composition_version,
      starting_lineup_snapshot = v_snapshot_map,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'start_match_live',
    v_actor,
    v_reason,
    jsonb_build_object('field_count', v_field_count)
  );

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.match_motm_opens_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  select match.kickoff_at + interval '1 hour 45 minutes'
  from public.matches match
  where match.id = p_match_id;
$function$;

create or replace function public.internal_push_dispatch(
  p_kind text,
  p_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_winner_names text;
  v_winner_count integer := 0;
  v_home_name text;
  v_away_name text;
  v_home_score text;
  v_away_score text;
begin
  select
    match.id,
    match.season_id,
    match.kickoff_at,
    match.score_as_grinta,
    match.score_adverse,
    match.location,
    opponent.name as opponent_name
  into v_match
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if p_kind in ('motm_open', 'motm_reminder', 'motm_results')
     and not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'payload', '{}'::jsonb,
      'subscriptions', '[]'::jsonb
    );
  end if;

  if p_kind = 'closing_soon' then
    v_payload := jsonb_build_object(
      'title', 'Dernière chance de pronostiquer',
      'body', format(
        'AS Grinta – %s : les pronostics ferment à %s.',
        v_match.opponent_name,
        to_char(
          (v_match.kickoff_at - interval '5 minutes')
            at time zone 'Europe/Paris',
          'HH24hMI'
        )
      ),
      'url', 'matches/' || p_match_id || '/lineup?section=prediction',
      'tag', 'match-' || v_match.id || '-closing'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and profile.notify_prediction_reminders
      and not exists (
        select 1
        from public.match_predictions prediction
        where prediction.match_id = p_match_id
          and prediction.profile_id = profile.id
          and prediction.is_filled
      );

  elsif p_kind = 'result_validated' then
    if v_match.location = 'exterieur' then
      v_home_name := v_match.opponent_name;
      v_away_name := 'AS Grinta';
      v_home_score := coalesce(v_match.score_adverse::text, '?');
      v_away_score := coalesce(v_match.score_as_grinta::text, '?');
    else
      v_home_name := 'AS Grinta';
      v_away_name := v_match.opponent_name;
      v_home_score := coalesce(v_match.score_as_grinta::text, '?');
      v_away_score := coalesce(v_match.score_adverse::text, '?');
    end if;

    v_payload := jsonb_build_object(
      'title', 'Score final',
      'body', format(
        'Score final : %s %s-%s %s.',
        v_home_name,
        v_home_score,
        v_away_score,
        v_away_name
      ),
      'url', '.',
      'tag', 'match-' || v_match.id || '-result'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active';

  elsif p_kind = 'motm_open' then
    if not exists (
      select 1
      from public.match_sport_motm_elections election
      where election.match_id = p_match_id
        and election.state = 'open'
        and now() >= election.opens_at
        and now() < election.closes_at
    ) then
      return jsonb_build_object(
        'payload', '{}'::jsonb,
        'subscriptions', '[]'::jsonb
      );
    end if;

    v_payload := jsonb_build_object(
      'title', 'Vote Homme du match',
      'body', format(
        'Vote pour l''Homme du Match — AS Grinta contre %s.',
        v_match.opponent_name
      ),
      'url', 'matches/' || p_match_id || '/vote',
      'tag', 'sport-' || p_match_id || '-motm-open'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player
          on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and participant.final_presence_status = 'present'
          and player.profile_id = profile.id
      );

  elsif p_kind = 'motm_reminder' then
    if not exists (
      select 1
      from public.match_sport_motm_elections election
      where election.match_id = p_match_id
        and election.state = 'open'
        and now() < election.closes_at
    ) then
      return jsonb_build_object(
        'payload', '{}'::jsonb,
        'subscriptions', '[]'::jsonb
      );
    end if;

    v_payload := jsonb_build_object(
      'title', 'Dernières heures pour voter',
      'body', format(
        'AS Grinta – %s : pense à voter pour l''Homme du Match.',
        v_match.opponent_name
      ),
      'url', 'matches/' || p_match_id || '/vote',
      'tag', 'sport-' || p_match_id || '-motm-reminder'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player
          on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and participant.final_presence_status = 'present'
          and player.profile_id = profile.id
      )
      and not exists (
        select 1
        from public.match_sport_motm_votes vote
        where vote.match_id = p_match_id
          and vote.voter_profile_id = profile.id
      );

  elsif p_kind = 'motm_results' then
    select
      string_agg(w.display_name, ', ' order by lower(w.display_name)),
      count(*)::integer
    into v_winner_names, v_winner_count
    from (
      select case
        when guest.id is not null then
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
        else coalesce(
          nullif(btrim(profile.surnom), ''),
          nullif(btrim(player.first_name), ''),
          btrim(concat_ws(' ', player.first_name, player.last_name))
        )
      end as display_name
      from public.match_sport_motm_results result
      join public.match_sport_participants participant
        on participant.id = result.participant_id
       and participant.match_id = result.match_id
      left join public.season_players player
        on player.id = participant.season_player_id
      left join public.profiles profile on profile.id = player.profile_id
      left join public.guest_players guest
        on guest.id = participant.guest_player_id
      where result.match_id = p_match_id
        and result.is_winner
    ) w;

    v_payload := jsonb_build_object(
      'title', case
        when v_winner_count > 1 then 'Co-Hommes du match'
        else 'Homme du match'
      end,
      'body', case
        when v_winner_count = 0 then
          format(
            'AS Grinta – %s : aucun Homme du match n''a été élu.',
            v_match.opponent_name
          )
        when v_winner_count = 1 then
          format('Bravo à %s, élu Homme du Match !', v_winner_names)
        else
          format('Bravo à %s, élus Hommes du Match !', v_winner_names)
      end,
      'url', 'matches/' || p_match_id || '/vote',
      'tag', 'sport-' || p_match_id || '-motm-results'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and exists (
        select 1
        from public.match_sport_motm_votes vote
        where vote.match_id = p_match_id
          and vote.voter_profile_id = profile.id
      );

  else
    raise exception 'Unknown notification kind: %', p_kind
      using errcode = '22023';
  end if;

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', coalesce(v_subscriptions, '[]'::jsonb)
  );
end;
$function$;

create or replace function private.process_match_motm_jobs(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_transitions integer;
  v_reminders integer;
begin
  v_transitions := private.close_due_match_motm_elections();
  v_reminders := private.push_due_motm_reminders(p_now);

  return jsonb_build_object(
    'transitions', v_transitions,
    'reminders', v_reminders
  );
end;
$function$;

revoke all on function private.process_match_motm_jobs(timestamptz)
  from public, anon, authenticated;

do $do$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid
    from cron.job
    where jobname in (
      'push-closing-reminders',
      'prediction-closing-reminders',
      'sports-close-motm-votes',
      'sports-motm-push-reminders',
      'sports-motm-jobs'
    )
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'prediction-closing-reminders',
    '* * * * *',
    $cron$select public.push_closing_reminders();$cron$
  );

  perform cron.schedule(
    'sports-motm-jobs',
    '* * * * *',
    $cron$select private.process_match_motm_jobs(now());$cron$
  );
end;
$do$;

commit;
