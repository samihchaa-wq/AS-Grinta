-- Harden the cross-stage match lifecycle now that sports management is a
-- permanent product capability.
--
-- 1. Normal match create/update always keeps the sports workflow in sync,
--    even when an older client omits the squad-size parameter.
-- 2. Live startup reconciles a published composition with late convocation
--    withdrawals/promotions before the session can start.
-- 3. Post-match statistics accept historical season players who participated
--    in the match even if they were deactivated before validation.
-- 4. Internal matches are never valid prediction targets.

create or replace function private.resolve_match_squad_size_limit(
  p_requested integer default null
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_config jsonb;
  v_resolved integer := 14;
begin
  if p_requested is not null then
    if p_requested < 1 or p_requested > 30 then
      raise exception 'Squad size limit must be between 1 and 30'
        using errcode = '22023';
    end if;
    return p_requested;
  end if;

  select flag.config
  into v_config
  from private.app_feature_flags flag
  where flag.key = 'sports_management';

  if coalesce(v_config ->> 'usual_squad_size', '') ~ '^[0-9]+$' then
    v_resolved := greatest(
      1,
      least(30, (v_config ->> 'usual_squad_size')::integer)
    );
  end if;

  return v_resolved;
end;
$function$;

revoke all on function private.resolve_match_squad_size_limit(integer)
  from public, anon, authenticated;

create or replace function public.admin_create_match_complete(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer default null,
  p_address text default null,
  p_remember_address_as_default boolean default false,
  p_match_type text default 'championnat',
  p_jersey_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_squad_size_limit integer;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_squad_size_limit := private.resolve_match_squad_size_limit(
    p_squad_size_limit
  );

  v_match_id := private.create_match_with_sport_limit(
    p_season_id,
    p_opponent_id,
    p_match_date,
    p_match_time,
    p_location,
    p_win,
    p_draw,
    p_loss,
    v_squad_size_limit
  );

  perform public.admin_set_match_address(
    v_match_id, p_address, p_remember_address_as_default
  );
  perform public.admin_set_match_type(v_match_id, p_match_type);
  perform public.admin_set_match_jersey(v_match_id, p_jersey_note);

  return v_match_id;
end;
$function$;

create or replace function public.admin_update_match_complete(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_expected_updated_at timestamp with time zone,
  p_squad_size_limit integer default null,
  p_address text default null,
  p_remember_address_as_default boolean default false,
  p_match_type text default 'championnat',
  p_jersey_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
  v_updated_at timestamptz;
  v_squad_size_limit integer;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Recharge le match avant de l’enregistrer.' using errcode = '40001';
  end if;

  select match.status, match.kickoff_at, match.updated_at
  into v_status, v_kickoff_at, v_updated_at
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_updated_at is distinct from p_expected_updated_at then
    raise exception 'Un autre administrateur a modifié ce match. Recharge l’écran avant d’enregistrer.'
      using errcode = '40001';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'Un match passé ou annulé ne se modifie plus depuis la fiche match.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is not null
     and now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  v_squad_size_limit := private.resolve_match_squad_size_limit(
    p_squad_size_limit
  );

  perform private.update_match_with_sport_limit(
    p_match_id,
    p_season_id,
    p_opponent_id,
    p_match_date,
    p_match_time,
    p_location,
    p_status,
    p_win,
    p_draw,
    p_loss,
    v_squad_size_limit
  );

  perform public.admin_set_match_address(
    p_match_id, p_address, p_remember_address_as_default
  );
  perform public.admin_set_match_type(p_match_id, p_match_type);
  perform public.admin_set_match_jersey(p_match_id, p_jersey_note);

  return true;
end;
$function$;

create or replace function private.open_match_live_workspace(
  p_match_id uuid,
  p_planned_duration_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_match_status text;
  v_kickoff_at timestamptz;
  v_default_duration integer;
  v_existing_state public.match_live_state;
  v_publication_snapshot jsonb;
  v_formation text;
  v_has_entries boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach, administrator or moderator role required'
      using errcode = '42501';
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

  select session.state
  into v_existing_state
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

    select exists (
      select 1
      from public.match_composition_entries entry
      where entry.match_id = p_match_id
    ) into v_has_entries;

    if v_has_entries then
      return private.match_live_snapshot(p_match_id);
    end if;
  end if;

  select publication.snapshot, publication.formation_code
  into v_publication_snapshot, v_formation
  from public.match_composition_publications publication
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_publication_snapshot is null then
    raise exception 'No published composition to start from'
      using errcode = '22023';
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
  )
  on conflict (match_id) do update
  set planned_duration_minutes = greatest(
        1,
        least(
          200,
          coalesce(
            p_planned_duration_minutes,
            match_live_sessions.planned_duration_minutes
          )
        )
      ),
      updated_by = v_actor,
      updated_at = now();

  -- Rebuild the operational Live lineup from the last publication, but apply
  -- the current convocation truth. A withdrawn player must never reappear just
  -- because the publication snapshot predates the withdrawal.
  delete from public.match_composition_entries
  where match_id = p_match_id;

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
    case
      when (entry ->> 'zone') in ('field', 'bench')
       and coalesce(participant.convocation_status::text, '') <> 'convoked'
        then 'not_selected'::public.sport_composition_zone
      else (entry ->> 'zone')::public.sport_composition_zone
    end,
    case
      when (entry ->> 'zone') = 'field'
       and participant.convocation_status = 'convoked'
        then (entry ->> 'x')::numeric
      else null
    end,
    case
      when (entry ->> 'zone') = 'field'
       and participant.convocation_status = 'convoked'
        then (entry ->> 'y')::numeric
      else null
    end,
    case
      when (entry ->> 'zone') = 'field'
       and participant.convocation_status = 'convoked'
        then entry ->> 'slot_label'
      else null
    end,
    coalesce((entry ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(v_publication_snapshot -> 'entries') entry
  left join public.match_sport_participants participant
    on participant.match_id = p_match_id
   and participant.id = (entry ->> 'participant_id')::uuid
  where (entry ->> 'zone') in ('field', 'bench', 'not_selected');

  -- A player promoted after a published withdrawal did not necessarily exist
  -- on that publication. Put that promoted, currently-convoked participant on
  -- the Live bench instead of silently omitting them.
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
    participant.id,
    'bench'::public.sport_composition_zone,
    null,
    null,
    null,
    900 + row_number() over (
      order by participant.promoted_after_withdrawal_at, participant.id
    )::integer
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.convocation_status = 'convoked'
    and participant.promoted_after_withdrawal_at is not null
    and not exists (
      select 1
      from public.match_composition_entries existing
      where existing.match_id = p_match_id
        and existing.participant_id = participant.id
        and existing.zone in ('field', 'bench')
    )
  on conflict (match_id, participant_id) do update
  set zone = 'bench',
      x = null,
      y = null,
      slot_label = null,
      sort_order = excluded.sort_order,
      updated_at = now();

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
set search_path = ''
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

  if exists (
    select 1
    from public.match_composition_entries entry
    left join public.match_sport_participants participant
      on participant.match_id = entry.match_id
     and participant.id = entry.participant_id
    where entry.match_id = p_match_id
      and entry.zone in ('field', 'bench')
      and coalesce(participant.convocation_status::text, '') <> 'convoked'
  ) then
    raise exception 'Live lineup is stale after a convocation change'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.match_sport_participants participant
    where participant.match_id = p_match_id
      and participant.is_eligible
      and participant.convocation_status = 'convoked'
      and participant.promoted_after_withdrawal_at is not null
      and not exists (
        select 1
        from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
  ) then
    raise exception 'Live lineup is missing a promoted player'
      using errcode = '22023';
  end if;

  select count(*) filter (where zone = 'field')
  into v_field_count
  from public.match_composition_entries
  where match_id = p_match_id;

  if v_field_count > 11 then
    raise exception 'A lineup cannot contain more than 11 starters'
      using errcode = '22023';
  end if;

  select composition.version
  into v_composition_version
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

create or replace function public.finalize_match_postgame(
  p_match_id uuid,
  p_score_adverse integer,
  p_scorers jsonb,
  p_clean_sheet_player_id uuid default null,
  p_score_as_grinta integer default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  item jsonb;
  match_season_id uuid;
  scorer_id uuid;
  scorer_goals integer;
  total_goals integer := 0;
  scorer_count integer := 0;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta < 0 or p_score_as_grinta > 99
     or p_score_adverse < 0 or p_score_adverse > 99 then
    raise exception 'Scores must be between 0 and 99' using errcode = '22023';
  end if;
  if p_scorers is null or jsonb_typeof(p_scorers) <> 'array' then
    raise exception 'Scorers payload must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_scorers) > 30 then
    raise exception 'Too many scorer entries' using errcode = '22023';
  end if;

  select match.season_id
  into match_season_id
  from public.matches match
  where match.id = p_match_id
    and match.status in ('a_venir', 'termine')
  for update;

  if not found then
    raise exception 'Only upcoming or finished matches can be validated'
      using errcode = 'P0002';
  end if;

  for item in select value from jsonb_array_elements(p_scorers)
  loop
    scorer_count := scorer_count + 1;
    if jsonb_typeof(item) <> 'object' then
      raise exception 'Each scorer entry must be an object' using errcode = '22023';
    end if;
    if not (item ? 'season_player_id') or not (item ? 'goals')
       or exists (
         select 1
         from jsonb_object_keys(item) as key
         where key not in ('season_player_id', 'goals')
       ) then
      raise exception 'Invalid scorer entry schema' using errcode = '22023';
    end if;
    if jsonb_typeof(item -> 'season_player_id') <> 'string'
       or jsonb_typeof(item -> 'goals') <> 'number'
       or (item ->> 'goals') !~ '^[0-9]+$' then
      raise exception 'Invalid scorer entry types' using errcode = '22023';
    end if;

    begin
      scorer_id := (item ->> 'season_player_id')::uuid;
      scorer_goals := (item ->> 'goals')::integer;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid scorer entry values' using errcode = '22023';
    end;

    if scorer_goals < 1 or scorer_goals > 99 then
      raise exception 'Scorer goals must be between 1 and 99' using errcode = '22023';
    end if;
    if not exists (
      select 1
      from public.season_players player
      where player.id = scorer_id
        and player.season_id = match_season_id
    ) then
      raise exception 'Scorer is not a player in the match season'
        using errcode = '22023';
    end if;

    total_goals := total_goals + scorer_goals;
    if total_goals > 99 or total_goals > p_score_as_grinta then
      raise exception 'Attributed goals exceed the AS Grinta score'
        using errcode = '22023';
    end if;
  end loop;

  if p_score_as_grinta = 0 and scorer_count > 0 then
    raise exception 'A score of zero cannot contain scorers' using errcode = '22023';
  end if;

  if p_clean_sheet_player_id is not null then
    if p_score_adverse <> 0 then
      raise exception 'Clean sheet is impossible when the opponent scored'
        using errcode = '22023';
    end if;
    if not exists (
      select 1
      from public.season_players player
      where player.id = p_clean_sheet_player_id
        and player.season_id = match_season_id
        and player.is_goalkeeper
    ) then
      raise exception 'Clean sheet must belong to a goalkeeper in the match season'
        using errcode = '22023';
    end if;
  end if;

  delete from public.match_player_stats
  where match_id = p_match_id;

  insert into public.match_player_stats(
    match_id,
    season_player_id,
    goals,
    clean_sheet
  )
  select
    p_match_id,
    (entry ->> 'season_player_id')::uuid,
    sum((entry ->> 'goals')::integer),
    false
  from jsonb_array_elements(p_scorers) as entry
  group by (entry ->> 'season_player_id')::uuid;

  if p_clean_sheet_player_id is not null then
    insert into public.match_player_stats(
      match_id,
      season_player_id,
      goals,
      clean_sheet
    ) values (
      p_match_id,
      p_clean_sheet_player_id,
      0,
      true
    )
    on conflict (match_id, season_player_id)
    do update set clean_sheet = true;
  end if;

  update public.matches
  set score_as_grinta = p_score_as_grinta,
      score_adverse = p_score_adverse,
      status = 'termine',
      predictions_closed_at = coalesce(predictions_closed_at, now()),
      result_validated_at = now(),
      updated_at = now()
  where id = p_match_id;

  return true;
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
set search_path = ''
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
    raise exception 'Les scores doivent être compris entre 0 et 99.' using errcode = '22023';
  end if;

  select *
  into v_match
  from public.matches
  where id = p_match_id
  for share;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_match.match_type = 'entre_nous' then
    raise exception 'Les matchs entre nous ne sont pas ouverts aux pronostics.'
      using errcode = '22023';
  end if;

  if v_match.kickoff_at is null
     or v_match.status <> 'a_venir'
     or now() < private.match_features_open_at(v_match.kickoff_at)
     or now() >= private.match_prediction_closes_at(v_match.kickoff_at)
     or (
       v_match.predictions_closed_at is not null
       and now() >= v_match.predictions_closed_at
     ) then
    raise exception 'Ce match n’est pas ouvert aux pronostics.'
      using errcode = '22023';
  end if;

  insert into public.match_predictions as existing (
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
      updated_at = now()
  where (
    existing.predicted_score_as_grinta,
    existing.predicted_score_adverse,
    existing.is_filled
  ) is distinct from (
    excluded.predicted_score_as_grinta,
    excluded.predicted_score_adverse,
    true
  );

  return true;
end;
$function$;

create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status <> 'active' then
    return new;
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled
  )
  select match.id, new.id, 0, 0, false
  from public.matches match
  where match.status = 'a_venir'
    and match.match_type <> 'entre_nous'
  on conflict (match_id, profile_id) do nothing;

  insert into public.season_predictions (
    season_id,
    predictor_profile_id,
    season_player_id,
    category,
    predicted_value_30,
    is_filled
  )
  select
    player.season_id,
    new.id,
    player.id,
    case when player.is_goalkeeper then 'clean_sheets' else 'buts' end,
    0,
    false
  from public.season_players player
  join public.seasons season
    on season.id = player.season_id
   and season.status = 'open'
  where player.is_active
  on conflict (
    season_id,
    predictor_profile_id,
    season_player_id,
    category
  ) do nothing;

  return new;
end;
$function$;

-- These rows were seeded only because the profile-activation trigger ignored
-- match_type. Internal matches have no valid prediction contract.
delete from public.match_predictions prediction
using public.matches match
where prediction.match_id = match.id
  and match.match_type = 'entre_nous';
