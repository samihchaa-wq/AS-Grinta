-- Live : seul le coach de la saison pilote, et il peut valider le compte rendu.
--
-- 1. Pilotage réservé au coach. Jusqu'ici un administrateur pouvait aussi
--    prendre la place de pilote. Désormais seuls les joueurs cochés « Coach »
--    dans l'effectif de la saison du match peuvent la prendre ou la reprendre.
--    Les administrateurs suivent le Live en spectateur. Toutes les autres
--    commandes Live exigent déjà d'être le pilote actuel : elles suivent.
--
-- 2. Validation du compte rendu par un coach non administrateur. La
--    validation passait bien les contrôles « coach ou admin » de
--    submit_match_sport_report et finalize_match_sport_postgame, puis échouait
--    plus loin dans trois fonctions réservées aux administrateurs (présences,
--    HDM vidé, score et buteurs). Ces trois fonctions acceptent maintenant le
--    contexte « coach du Live » que finalize_match_sport_postgame pose déjà
--    pour la durée de la transaction, uniquement pour un coach de ce match.
--
-- Chaque fonction est reprise à l'identique de sa définition en production
-- (vérifiée avant écriture) : seuls les contrôles d'accès changent. CREATE OR
-- REPLACE conserve les droits d'exécution existants.

begin;

-- ------------------------------------------------------------------ helpers

create or replace function private.is_match_live_pilot_coach(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.is_active_profile()
    and exists (
      select 1
      from public.season_players sp
      join public.matches m on m.season_id = sp.season_id
      where m.id = p_match_id
        and sp.profile_id = (select auth.uid())
        and sp.is_coach = true
        and sp.is_active = true
    );
$function$;

revoke all on function private.is_match_live_pilot_coach(uuid)
  from public, anon, authenticated;

comment on function private.is_match_live_pilot_coach(uuid) is
  'Vrai si le profil courant est coach actif de la saison du match. Seul ce profil peut piloter le Live.';

-- Écritures de fin de match : administrateur, ou coach du match pendant la
-- validation de son compte rendu (contexte posé par la fonction appelante
-- dans la même transaction, jamais par le client).
create or replace function private.can_write_match_postgame(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select public.is_match_staff()
    or (
      coalesce(current_setting('as_grinta.allow_coach_live_finalize', true), '') = 'on'
      and private.is_match_coach_or_admin(p_match_id)
    );
$function$;

revoke all on function private.can_write_match_postgame(uuid)
  from public, anon, authenticated;

-- ------------------------------------------------------ pilotage : coach seul

create or replace function public.claim_match_live_pilot(p_match_id uuid, p_planned_duration_minutes integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid := private.match_live_current_session_id();
  v_pilot_session_id uuid;
  v_heartbeat_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if v_actor is null or v_session_id is null or not private.is_active_profile() then
    raise exception 'Active authenticated session required' using errcode = '42501';
  end if;
  if not private.is_match_live_pilot_coach(p_match_id) then
    raise exception 'Seul le coach peut piloter le Live.' using errcode = '42501';
  end if;

  select session.pilot_session_id, session.pilot_heartbeat_at
  into v_pilot_session_id, v_heartbeat_at
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    -- Le premier coach qui ouvre Piloter crée l'espace de travail puis prend
    -- immédiatement le verrou. L'appel privé évite le problème circulaire :
    -- l'API publique open_match_live_workspace exige ensuite d'être pilote.
    perform private.open_match_live_workspace(
      p_match_id,
      p_planned_duration_minutes
    );

    select session.pilot_session_id, session.pilot_heartbeat_at
    into v_pilot_session_id, v_heartbeat_at
    from public.match_live_sessions session
    where session.match_id = p_match_id
    for update;
  end if;

  if v_pilot_session_id is not null
     and v_pilot_session_id is distinct from v_session_id
     and v_heartbeat_at is not null
     and v_heartbeat_at >= now() - interval '60 seconds' then
    return public.get_match_live_state(p_match_id);
  end if;

  update public.match_live_sessions
  set pilot_profile_id = v_actor,
      pilot_session_id = v_session_id,
      pilot_heartbeat_at = now(),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.take_over_match_live_pilot(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid := private.match_live_current_session_id();
begin
  perform private.require_sports_management_enabled();
  if v_actor is null or v_session_id is null or not private.is_active_profile() then
    raise exception 'Active authenticated session required' using errcode = '42501';
  end if;
  if not private.is_match_live_pilot_coach(p_match_id) then
    raise exception 'Seul le coach peut piloter le Live.' using errcode = '42501';
  end if;

  perform 1
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    perform private.open_match_live_workspace(p_match_id, null);
    perform 1
    from public.match_live_sessions session
    where session.match_id = p_match_id
    for update;
  end if;

  update public.match_live_sessions
  set pilot_profile_id = v_actor,
      pilot_session_id = v_session_id,
      pilot_heartbeat_at = now(),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  return public.get_match_live_state(p_match_id);
end;
$function$;

-- ------------------------------------ validation du compte rendu par le coach

create or replace function public.staff_set_match_attendance(p_match_id uuid, p_present uuid[])
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_season_id uuid;
  v_player uuid;
  v_profiles uuid[];
begin
  if not private.can_write_match_postgame(p_match_id) then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select season_id
  into v_season_id
  from public.matches
  where id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  select array_agg(distinct player.profile_id)
  into v_profiles
  from public.match_attendance attendance
  join public.season_players player
    on player.id = attendance.season_player_id
  where attendance.match_id = p_match_id
    and player.profile_id is not null;

  delete from public.match_attendance
  where match_id = p_match_id;

  if p_present is not null then
    foreach v_player in array p_present
    loop
      if not exists (
        select 1
        from public.season_players player
        where player.id = v_player
          and player.season_id = v_season_id
          and (
            player.is_active
            or exists (
              select 1
              from public.match_sport_participants participant
              where participant.match_id = p_match_id
                and participant.season_player_id = player.id
            )
          )
      ) then
        raise exception 'Player is not active in the match season'
          using errcode = '22023';
      end if;

      insert into public.match_attendance(match_id, season_player_id)
      values (p_match_id, v_player)
      on conflict do nothing;
    end loop;
  end if;

  select array_cat(
    coalesce(v_profiles, '{}'),
    coalesce(array_agg(distinct player.profile_id), '{}')
  )
  into v_profiles
  from public.season_players player
  where player.id = any (coalesce(p_present, '{}'))
    and player.profile_id is not null;

  if v_profiles is not null then
    foreach v_player in array v_profiles
    loop
      perform public.recalculate_profile_badges(v_player);
    end loop;
  end if;

  return true;
end;
$function$;

create or replace function public.staff_set_match_mvp(p_match_id uuid, p_players uuid[])
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_season_id uuid;
  v_player uuid;
  v_profiles uuid[];
begin
  if not private.can_write_match_postgame(p_match_id) then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select season_id into v_season_id from public.matches where id = p_match_id;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  select array_agg(distinct sp.profile_id)
  into v_profiles
  from public.match_man_of_match mvp
  join public.season_players sp on sp.id = mvp.season_player_id
  where mvp.match_id = p_match_id and sp.profile_id is not null;

  delete from public.match_man_of_match where match_id = p_match_id;

  if p_players is not null then
    foreach v_player in array p_players loop
      if not exists (
        select 1 from public.season_players sp
        where sp.id = v_player and sp.season_id = v_season_id and sp.is_active
      ) then
        raise exception 'Player is not active in the match season' using errcode = '22023';
      end if;
      insert into public.match_man_of_match(match_id, season_player_id)
      values (p_match_id, v_player)
      on conflict do nothing;
    end loop;
  end if;

  select array_cat(coalesce(v_profiles, '{}'), coalesce(array_agg(distinct sp.profile_id), '{}'))
  into v_profiles
  from public.season_players sp
  where sp.id = any (coalesce(p_players, '{}')) and sp.profile_id is not null;

  if v_profiles is not null then
    foreach v_player in array v_profiles loop
      perform public.recalculate_profile_badges(v_player);
    end loop;
  end if;

  return true;
end;
$function$;

create or replace function public.finalize_match_postgame(p_match_id uuid, p_score_adverse integer, p_scorers jsonb, p_clean_sheet_player_id uuid DEFAULT NULL::uuid, p_score_as_grinta integer DEFAULT NULL::integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  item jsonb;
  match_season_id uuid;
  scorer_id uuid;
  scorer_goals integer;
  total_goals integer := 0;
  scorer_count integer := 0;
begin
  if not private.can_write_match_postgame(p_match_id) then
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
        and (
          player.is_active
          or exists (
            select 1
            from public.match_attendance attendance
            where attendance.match_id = p_match_id
              and attendance.season_player_id = player.id
          )
        )
    ) then
      raise exception 'Scorer is not an active player in the match season'
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
        and (
          player.is_active
          or exists (
            select 1
            from public.match_attendance attendance
            where attendance.match_id = p_match_id
              and attendance.season_player_id = player.id
          )
        )
    ) then
      raise exception 'Clean sheet must belong to an active goalkeeper in the match season'
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

commit;
