-- Keep harmless administrative recovery for an empty season while making
-- prediction revelation and historical competition data irreversible as soon
-- as real participation exists.

create or replace function private.season_prediction_lock_is_committed(
  p_season_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.season_predictions prediction
      where prediction.season_id = p_season_id
        and prediction.is_filled
    )
    or exists (
      select 1
      from public.matches match
      where match.season_id = p_season_id
        and match.status <> 'annule'
        and match.kickoff_at is not null
        and match.kickoff_at <= now()
    );
$function$;

revoke all on function private.season_prediction_lock_is_committed(uuid)
  from public, anon, authenticated;

create or replace function private.season_has_historical_competition(
  p_season_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    private.season_prediction_lock_is_committed(p_season_id)
    or exists (
      select 1
      from public.match_predictions prediction
      join public.matches match on match.id = prediction.match_id
      where match.season_id = p_season_id
        and prediction.is_filled
    )
    or exists (
      select 1
      from public.season_awards award
      where award.season_id = p_season_id
    );
$function$;

revoke all on function private.season_has_historical_competition(uuid)
  from public, anon, authenticated;

create or replace function private.guard_season_competition_finality()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.status = 'archived'
     and new.status is distinct from old.status
     and private.season_has_historical_competition(old.id) then
    raise exception 'Une saison archivée avec des données de compétition ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  if old.season_predictions_locked_at is not null then
    if new.season_predictions_locked_at is null
       and private.season_prediction_lock_is_committed(old.id) then
      raise exception 'Les pronostics de saison révélés sont définitivement figés.'
        using errcode = '22023';
    end if;

    if new.season_predictions_locked_at is not null
       and new.season_predictions_locked_at is distinct from old.season_predictions_locked_at then
      raise exception 'La date de révélation des pronostics de saison est immuable.'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.set_season_predictions_lock(
  p_season_id uuid,
  p_locked boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_locked_at timestamptz;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_locked is null then
    raise exception 'Season id and lock value are required' using errcode = '22023';
  end if;

  select season.season_predictions_locked_at
  into v_locked_at
  from public.seasons season
  where season.id = p_season_id
    and season.status = 'open'
  for update;

  if not found then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;

  if p_locked then
    if v_locked_at is null then
      update public.seasons
      set season_predictions_locked_at = now()
      where id = p_season_id;
    end if;
    return true;
  end if;

  if v_locked_at is null then
    return true;
  end if;

  if private.season_prediction_lock_is_committed(p_season_id) then
    raise exception 'Les pronostics de saison révélés sont définitivement figés.'
      using errcode = '22023';
  end if;

  update public.seasons
  set season_predictions_locked_at = null
  where id = p_season_id;

  return true;
end;
$function$;

create or replace function private.sync_season_prediction_roster_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- An empty pre-season lock can still be undone safely. In that narrow case,
  -- remove its empty competition contract so a later lock can capture the
  -- then-current roster.
  if old.season_predictions_locked_at is not null
     and new.season_predictions_locked_at is null
  then
    if private.season_prediction_lock_is_committed(new.id) then
      raise exception 'Les pronostics de saison révélés sont définitivement figés.'
        using errcode = '22023';
    end if;

    delete from public.season_prediction_roster_captures
    where season_id = new.id;
    return new;
  end if;

  if old.season_predictions_locked_at is null
     and new.season_predictions_locked_at is not null
     and not exists (
       select 1
       from public.season_prediction_roster_captures capture
       where capture.season_id = new.id
     )
  then
    insert into public.season_prediction_roster_captures(
      season_id, captured_at, capture_reason
    ) values (new.id, new.season_predictions_locked_at, 'lock');

    insert into public.season_prediction_roster_members(
      season_id, season_player_id, category
    )
    select
      player.season_id,
      player.id,
      case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
    from public.season_players player
    where player.season_id = new.id
      and player.is_active;

    return new;
  end if;

  if old.status is distinct from 'archived'
     and new.status = 'archived'
     and not exists (
       select 1
       from public.season_prediction_roster_captures capture
       where capture.season_id = new.id
     )
  then
    insert into public.season_prediction_roster_captures(
      season_id, captured_at, capture_reason
    ) values (new.id, now(), 'archive');

    insert into public.season_prediction_roster_members(
      season_id, season_player_id, category
    )
    select
      player.season_id,
      player.id,
      case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
    from public.season_players player
    where player.season_id = new.id
      and player.is_active;
  end if;

  return new;
end;
$function$;

create or replace function public.set_season_status(
  p_season_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null then
    raise exception 'Season id is required' using errcode = '22023';
  end if;
  if p_status is null or p_status not in ('open', 'terminee', 'archived') then
    raise exception 'Statut de saison invalide' using errcode = '22023';
  end if;

  select season.status
  into v_current_status
  from public.seasons season
  where season.id = p_season_id
  for update;

  if not found then
    raise exception 'Season not found' using errcode = 'P0002';
  end if;

  if v_current_status = p_status then
    return true;
  end if;

  if p_status = 'open'
     and v_current_status <> 'open'
     and private.season_has_historical_competition(p_season_id) then
    raise exception 'Une saison avec des données de compétition ne peut pas être rouverte.'
      using errcode = '22023';
  end if;

  if p_status = 'open' then
    update public.seasons
    set status = 'archived'
    where status = 'open'
      and id <> p_season_id;
  end if;

  update public.seasons
  set status = p_status
  where id = p_season_id;

  return true;
end;
$function$;

create or replace function public.open_or_create_season(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  season_name text := btrim(coalesce(p_name, ''));
  start_year integer;
  end_year integer;
  season_id uuid;
  season_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if season_name !~ '^[0-9]{4}-[0-9]{4}$' then
    raise exception 'Le nom doit respecter le format 2026-2027' using errcode = '22023';
  end if;

  start_year := substring(season_name from 1 for 4)::integer;
  end_year := substring(season_name from 6 for 4)::integer;
  if end_year <> start_year + 1 then
    raise exception 'La saison doit couvrir deux années consécutives' using errcode = '22023';
  end if;
  if start_year < 2000 or start_year > 2100 then
    raise exception 'Année de saison hors limites' using errcode = '22023';
  end if;

  select season.id, season.status
  into season_id, season_status
  from public.seasons season
  where season.name = season_name
  for update;

  if found then
    if season_status <> 'open'
       and private.season_has_historical_competition(season_id) then
      raise exception 'Une saison avec des données de compétition ne peut pas être rouverte.'
        using errcode = '22023';
    end if;

    update public.seasons
    set status = 'archived'
    where status = 'open'
      and id <> season_id;

    update public.seasons
    set status = 'open',
        season_predictions_locked_at = case
          when season_predictions_locked_at is not null
               and private.season_prediction_lock_is_committed(id)
            then season_predictions_locked_at
          else null
        end
    where id = season_id;

    return season_id;
  end if;

  update public.seasons
  set status = 'archived'
  where status = 'open';

  insert into public.seasons(name, status)
  values (season_name, 'open')
  returning id into season_id;

  return season_id;
end;
$function$;
