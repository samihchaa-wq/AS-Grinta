-- Baseline structurelle minimale pour les tests métier et RLS.
-- Aucun contenu de production n'est copié dans ce fichier.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgtap with schema extensions;
create schema if not exists private;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  email text not null unique,
  photo_url text,
  role text not null default 'pronostiqueur'
    check (role in ('pronostiqueur', 'admin')),
  is_goalkeeper boolean not null default false,
  status text not null default 'active'
    check (status in ('pending', 'active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  surnom text,
  notify_match_reminders boolean not null default true,
  notify_prediction_reminders boolean not null default true,
  username text unique,
  password_set boolean not null default true,
  notify_prediction_open boolean not null default true,
  must_change_password boolean not null default false
);

create table public.seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  status text not null default 'open'
    check (status in ('open', 'terminee', 'archived')),
  created_at timestamptz not null default now(),
  season_predictions_locked_at timestamptz
);
create unique index seasons_single_open_idx
  on public.seasons(status) where status = 'open';

create table public.opponents (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.season_players (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  is_goalkeeper boolean not null default false,
  joined_at timestamptz not null default now(),
  first_name text not null,
  last_name text not null,
  is_active boolean not null default true,
  position integer,
  profile_id uuid references public.profiles(id) on delete set null
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  opponent_id uuid not null references public.opponents(id) on delete restrict,
  match_date date not null,
  match_time time without time zone,
  location text not null check (location in ('domicile', 'exterieur')),
  planned_duration_minutes integer not null default 90
    check (planned_duration_minutes > 0),
  status text not null default 'a_venir'
    check (status in ('a_venir', 'termine', 'archive')),
  score_as_grinta integer check (score_as_grinta between 0 and 99),
  score_adverse integer check (score_adverse between 0 and 99),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  competition text default 'Championnat',
  result_validated_at timestamptz,
  predictions_closed_at timestamptz
);
create unique index matches_match_date_uidx on public.matches(match_date);

create table public.match_odds (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null unique references public.matches(id) on delete cascade,
  odds_victoire_as_grinta numeric not null check (odds_victoire_as_grinta >= 1),
  odds_nul numeric not null check (odds_nul >= 1),
  odds_victoire_adverse numeric not null check (odds_victoire_adverse >= 1),
  computed_at timestamptz not null default now(),
  probability_win numeric,
  probability_draw numeric,
  probability_loss numeric,
  expected_goals_as_grinta numeric,
  expected_goals_adverse numeric,
  confidence numeric,
  model_version text not null default 'legacy'
);

create table public.match_predictions (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  predicted_score_as_grinta integer not null default 0
    check (predicted_score_as_grinta between 0 and 99),
  predicted_score_adverse integer not null default 0
    check (predicted_score_adverse between 0 and 99),
  is_filled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  use_x2 boolean not null default false,
  unique(match_id, profile_id)
);

create table public.season_predictions (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  predictor_profile_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (category in ('buts', 'clean_sheets')),
  predicted_value_30 integer not null default 0 check (predicted_value_30 >= 0),
  is_filled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  season_player_id uuid not null references public.season_players(id) on delete cascade,
  unique(season_id, predictor_profile_id, season_player_id, category)
);

create table public.match_attendance (
  match_id uuid not null references public.matches(id) on delete cascade,
  season_player_id uuid not null references public.season_players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(match_id, season_player_id)
);

create table public.match_man_of_match (
  match_id uuid not null references public.matches(id) on delete cascade,
  season_player_id uuid not null references public.season_players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(match_id, season_player_id)
);

create table public.match_player_stats (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  goals integer not null default 0 check (goals >= 0),
  clean_sheet boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  season_player_id uuid not null references public.season_players(id) on delete cascade,
  unique(match_id, season_player_id)
);

create table public.push_notification_log (
  match_id uuid not null references public.matches(id) on delete cascade,
  kind text not null,
  created_at timestamptz not null default now(),
  primary key(match_id, kind)
);

create or replace function private.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.status = 'active'
  );
$function$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.status = 'active'
  );
$function$;

create or replace function private.is_match_staff()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.is_admin();
$function$;

create or replace function public.is_match_staff()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.is_match_staff();
$function$;

revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;
revoke execute on all functions in schema private from public, anon;
grant execute on function private.is_active_profile() to authenticated, service_role;
grant execute on function private.is_admin() to authenticated, service_role;
grant execute on function private.is_match_staff() to authenticated, service_role;
revoke execute on function public.is_match_staff() from public, anon;
grant execute on function public.is_match_staff() to authenticated, service_role;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.profiles(
    id, email, first_name, last_name, role, is_goalkeeper, status
  ) values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    'pronostiqueur',
    false,
    'pending'
  )
  on conflict (id) do update
  set email = excluded.email,
      first_name = case
        when public.profiles.first_name = '' then excluded.first_name
        else public.profiles.first_name
      end,
      last_name = case
        when public.profiles.last_name = '' then excluded.last_name
        else public.profiles.last_name
      end,
      updated_at = now();
  return new;
end;
$function$;

create trigger on_auth_user_created
after insert or update of email, raw_user_meta_data on auth.users
for each row execute function public.handle_new_auth_user();
revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;

create or replace function public.guard_sensitive_profile_fields()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid := (select auth.uid());
  old_protected jsonb;
  new_protected jsonb;
begin
  if actor_id is null then
    return new;
  end if;
  if public.is_match_staff() then
    return new;
  end if;
  if actor_id is distinct from old.id then
    raise exception 'Un utilisateur ne peut modifier que son propre profil.'
      using errcode = '42501';
  end if;
  old_protected := to_jsonb(old) - array[
    'first_name', 'last_name', 'surnom', 'updated_at',
    'notify_prediction_open', 'notify_prediction_reminders',
    'notify_match_reminders', 'password_set', 'must_change_password'
  ];
  new_protected := to_jsonb(new) - array[
    'first_name', 'last_name', 'surnom', 'updated_at',
    'notify_prediction_open', 'notify_prediction_reminders',
    'notify_match_reminders', 'password_set', 'must_change_password'
  ];
  if new_protected is distinct from old_protected then
    raise exception 'Les champs sensibles du profil ne peuvent pas être modifiés.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

create trigger trg_guard_sensitive_profile_fields
before update on public.profiles
for each row execute function public.guard_sensitive_profile_fields();
revoke execute on function public.guard_sensitive_profile_fields()
  from public, anon, authenticated;

-- Fonctions de préremplissage préexistantes : #287 remplace leur corps.
create or replace function public.seed_match_predictions()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.match_predictions(
    match_id, profile_id, predicted_score_as_grinta,
    predicted_score_adverse, is_filled, use_x2
  )
  select new.id, p.id, 0, 0, false, false
  from public.profiles p
  where p.status = 'active'
  on conflict(match_id, profile_id) do nothing;
  return new;
end;
$function$;

create trigger trg_seed_match_predictions
after insert on public.matches
for each row execute function public.seed_match_predictions();

create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status <> 'active' then return new; end if;
  insert into public.match_predictions(
    match_id, profile_id, predicted_score_as_grinta,
    predicted_score_adverse, is_filled, use_x2
  )
  select m.id, new.id, 0, 0, false, false
  from public.matches m
  where m.status = 'a_venir'
  on conflict(match_id, profile_id) do nothing;
  return new;
end;
$function$;

create trigger trg_seed_predictions_for_active_profile
after insert or update of status, role on public.profiles
for each row execute function public.seed_predictions_for_active_profile();

-- Le trigger x2 existe avant #284/#287 ; son corps est remplacé par les migrations.
create or replace function public.enforce_match_prediction_x2()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  return new;
end;
$function$;

create trigger trg_enforce_match_prediction_x2
before insert or update of use_x2 on public.match_predictions
for each row execute function public.enforce_match_prediction_x2();

create or replace function public.internal_push_notify(p_kind text, p_match_id uuid)
returns boolean
language sql
security definer
set search_path to ''
as $function$
  select true;
$function$;
revoke execute on function public.internal_push_notify(text, uuid)
  from public, anon, authenticated;

create or replace function public.create_match_with_odds(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  new_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_opponent_id is null
     or p_match_date is null or p_match_time is null then
    raise exception 'Season, opponent, date and time are required'
      using errcode = '22023';
  end if;
  if p_location is null or p_location not in ('domicile', 'exterieur') then
    raise exception 'Invalid location' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Match date is outside allowed bounds' using errcode = '22023';
  end if;
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Invalid odds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.seasons s
    where s.id = p_season_id and s.status = 'open'
  ) then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;
  insert into public.matches(
    season_id, opponent_id, match_date, match_time, location,
    planned_duration_minutes, status, created_by
  ) values (
    p_season_id, p_opponent_id, p_match_date, p_match_time, p_location,
    90, 'a_venir', (select auth.uid())
  ) returning id into new_id;
  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul,
    odds_victoire_adverse, computed_at
  ) values (
    new_id, round(p_win, 2), round(p_draw, 2), round(p_loss, 2), now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();
  return new_id;
end;
$function$;

create or replace function public.close_match_predictions(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  update public.matches
  set predictions_closed_at = now(), updated_at = now()
  where id = p_match_id
    and status = 'a_venir'
    and predictions_closed_at is null;
  if not found then
    raise exception 'Open upcoming match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;

create or replace function public.staff_set_match_attendance(
  p_match_id uuid,
  p_present uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_season_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  select season_id into v_season_id from public.matches where id = p_match_id;
  if v_season_id is null then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_present, '{}'::uuid[])) player_id
    where not exists (
      select 1 from public.season_players sp
      where sp.id = player_id and sp.season_id = v_season_id and sp.is_active
    )
  ) then
    raise exception 'Attendance contains an invalid player' using errcode = '22023';
  end if;
  delete from public.match_attendance where match_id = p_match_id;
  insert into public.match_attendance(match_id, season_player_id)
  select p_match_id, distinct_player
  from (
    select distinct unnest(coalesce(p_present, '{}'::uuid[])) as distinct_player
  ) players
  where distinct_player is not null;
  return true;
end;
$function$;

create or replace function public.staff_set_match_mvp(
  p_match_id uuid,
  p_players uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_season_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  select season_id into v_season_id from public.matches where id = p_match_id;
  if v_season_id is null then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_players, '{}'::uuid[])) player_id
    where not exists (
      select 1 from public.season_players sp
      where sp.id = player_id and sp.season_id = v_season_id and sp.is_active
    )
  ) then
    raise exception 'MVP contains an invalid player' using errcode = '22023';
  end if;
  delete from public.match_man_of_match where match_id = p_match_id;
  insert into public.match_man_of_match(match_id, season_player_id)
  select p_match_id, distinct_player
  from (
    select distinct unnest(coalesce(p_players, '{}'::uuid[])) as distinct_player
  ) players
  where distinct_player is not null;
  return true;
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
set search_path to ''
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
  select m.season_id into match_season_id
  from public.matches m
  where m.id = p_match_id and m.status in ('a_venir', 'termine')
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
         select 1 from jsonb_object_keys(item) as key
         where key not in ('season_player_id', 'goals')
       ) then
      raise exception 'Invalid scorer entry schema' using errcode = '22023';
    end if;
    if jsonb_typeof(item->'season_player_id') <> 'string'
       or jsonb_typeof(item->'goals') <> 'number'
       or (item->>'goals') !~ '^[0-9]+$' then
      raise exception 'Invalid scorer entry types' using errcode = '22023';
    end if;
    begin
      scorer_id := (item->>'season_player_id')::uuid;
      scorer_goals := (item->>'goals')::integer;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid scorer entry values' using errcode = '22023';
    end;
    if scorer_goals < 1 or scorer_goals > 99 then
      raise exception 'Scorer goals must be between 1 and 99' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.id = scorer_id
        and sp.season_id = match_season_id
        and sp.is_active
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
      select 1 from public.season_players sp
      where sp.id = p_clean_sheet_player_id
        and sp.season_id = match_season_id
        and sp.is_goalkeeper
        and sp.is_active
    ) then
      raise exception 'Clean sheet must belong to an active goalkeeper in the match season'
        using errcode = '22023';
    end if;
  end if;
  delete from public.match_player_stats where match_id = p_match_id;
  insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
  select p_match_id,
         (entry->>'season_player_id')::uuid,
         sum((entry->>'goals')::integer),
         false
  from jsonb_array_elements(p_scorers) as entry
  group by (entry->>'season_player_id')::uuid;
  if p_clean_sheet_player_id is not null then
    insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
    values (p_match_id, p_clean_sheet_player_id, 0, true)
    on conflict (match_id, season_player_id) do update set clean_sheet = true;
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

create or replace function public.finalize_match_postgame_with_lineup(
  p_match_id uuid,
  p_score_adverse integer,
  p_scorers jsonb,
  p_clean_sheet_player_id uuid default null,
  p_score_as_grinta integer default null,
  p_present uuid[] default '{}'::uuid[],
  p_man_of_match_player_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_scorer jsonb;
  v_scorer_id uuid;
  v_mvp_players uuid[];
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if p_present is null or cardinality(p_present) = 0 then
    raise exception 'At least one present player is required' using errcode = '22023';
  end if;
  if array_position(p_present, null) is not null then
    raise exception 'Present players cannot contain null values' using errcode = '22023';
  end if;
  if p_scorers is null or jsonb_typeof(p_scorers) <> 'array' then
    raise exception 'Scorers payload must be a JSON array' using errcode = '22023';
  end if;
  for v_scorer in select value from jsonb_array_elements(p_scorers)
  loop
    begin
      v_scorer_id := (v_scorer->>'season_player_id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Invalid scorer player id' using errcode = '22023';
    end;
    if not (v_scorer_id = any(p_present)) then
      raise exception 'Every scorer must be marked as present' using errcode = '22023';
    end if;
  end loop;
  if p_clean_sheet_player_id is not null
     and not (p_clean_sheet_player_id = any(p_present)) then
    raise exception 'The clean sheet goalkeeper must be marked as present'
      using errcode = '22023';
  end if;
  if p_man_of_match_player_id is not null
     and not (p_man_of_match_player_id = any(p_present)) then
    raise exception 'The man of the match must be marked as present'
      using errcode = '22023';
  end if;
  perform public.staff_set_match_attendance(p_match_id, p_present);
  v_mvp_players := case
    when p_man_of_match_player_id is null then '{}'::uuid[]
    else array[p_man_of_match_player_id]
  end;
  perform public.staff_set_match_mvp(p_match_id, v_mvp_players);
  return public.finalize_match_postgame(
    p_match_id,
    p_score_adverse,
    p_scorers,
    p_clean_sheet_player_id,
    p_score_as_grinta
  );
end;
$function$;

revoke execute on function public.create_match_with_odds(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric
) from public, anon;
revoke execute on function public.close_match_predictions(uuid) from public, anon;
revoke execute on function public.staff_set_match_attendance(uuid, uuid[]) from public, anon;
revoke execute on function public.staff_set_match_mvp(uuid, uuid[]) from public, anon;
revoke execute on function public.finalize_match_postgame(
  uuid, integer, jsonb, uuid, integer
) from public, anon;
revoke execute on function public.finalize_match_postgame_with_lineup(
  uuid, integer, jsonb, uuid, integer, uuid[], uuid
) from public, anon;

grant execute on function public.create_match_with_odds(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric
) to authenticated, service_role;
grant execute on function public.close_match_predictions(uuid)
  to authenticated, service_role;
grant execute on function public.staff_set_match_attendance(uuid, uuid[])
  to authenticated, service_role;
grant execute on function public.staff_set_match_mvp(uuid, uuid[])
  to authenticated, service_role;
grant execute on function public.finalize_match_postgame(
  uuid, integer, jsonb, uuid, integer
) to authenticated, service_role;
grant execute on function public.finalize_match_postgame_with_lineup(
  uuid, integer, jsonb, uuid, integer, uuid[], uuid
) to authenticated, service_role;

alter table public.profiles enable row level security;
alter table public.seasons enable row level security;
alter table public.opponents enable row level security;
alter table public.season_players enable row level security;
alter table public.matches enable row level security;
alter table public.match_odds enable row level security;
alter table public.match_predictions enable row level security;
alter table public.season_predictions enable row level security;
alter table public.match_attendance enable row level security;
alter table public.match_man_of_match enable row level security;
alter table public.match_player_stats enable row level security;

grant select, update on public.profiles to authenticated;
grant select on public.seasons, public.opponents, public.season_players,
  public.matches, public.match_odds, public.match_attendance,
  public.match_man_of_match, public.match_player_stats to authenticated;
grant select, insert, update on public.match_predictions to authenticated;
grant select, insert, update on public.season_predictions to authenticated;
grant all on all tables in schema public to service_role;

create policy authenticated_read_profiles
on public.profiles for select to authenticated using (true);
create policy profiles_update_authorized
on public.profiles for update to authenticated
using (id = (select auth.uid()) or (select private.is_match_staff()))
with check (id = (select auth.uid()) or (select private.is_match_staff()));

create policy authenticated_read_seasons
on public.seasons for select to authenticated using (true);
create policy authenticated_read_opponents
on public.opponents for select to authenticated using (true);
create policy authenticated_read_season_players
on public.season_players for select to authenticated using (true);
create policy authenticated_read_matches
on public.matches for select to authenticated using (true);
create policy authenticated_read_match_odds
on public.match_odds for select to authenticated using (true);
create policy match_attendance_read
on public.match_attendance for select to authenticated using (true);
create policy match_mvp_read
on public.match_man_of_match for select to authenticated using (true);
create policy match_player_stats_read
on public.match_player_stats for select to authenticated using (true);

create policy read_own_or_revealed_match_predictions
on public.match_predictions for select to authenticated
using (
  profile_id = (select auth.uid())
  or exists (
    select 1 from public.matches m
    where m.id = match_predictions.match_id
      and m.status in ('termine', 'archive')
  )
);

create policy match_predictions_owner_insert
on public.match_predictions for insert to authenticated
with check (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
);
create policy match_predictions_owner_update_window
on public.match_predictions for update to authenticated
using (profile_id = (select auth.uid()))
with check (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
);

create policy read_own_season_predictions
on public.season_predictions for select to authenticated
using (predictor_profile_id = (select auth.uid()));
create policy own_season_predictions_insert
on public.season_predictions for insert to authenticated
with check (predictor_profile_id = (select auth.uid()));
create policy own_season_predictions_update
on public.season_predictions for update to authenticated
using (predictor_profile_id = (select auth.uid()))
with check (predictor_profile_id = (select auth.uid()));

-- Dans la suite, le troisième argument de throws_ok est une description.
-- Cette surcharge locale vérifie uniquement le SQLSTATE, puis transmet la description.
create or replace function public.throws_ok(
  p_sql text,
  p_errcode text,
  p_description text
)
returns text
language sql
as $function$
  select extensions.throws_ok(
    p_sql,
    p_errcode::char(5),
    null::text,
    p_description
  );
$function$;
