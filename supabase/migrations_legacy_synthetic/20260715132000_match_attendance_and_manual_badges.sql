-- Présences (feuille de match) découplées de finalize_match_postgame, et RPC
-- d'attribution manuelle des badges. Aucune modification de la fonction de
-- validation existante (qui réécrit match_player_stats) : les présences vivent
-- dans leur propre table.

-- La colonne 'played' n'est plus utilisée (remplacée par match_attendance).
alter table public.match_player_stats drop column if exists played;

create table if not exists public.match_attendance (
  match_id uuid not null references public.matches(id) on delete cascade,
  season_player_id uuid not null references public.season_players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (match_id, season_player_id)
);

create index if not exists match_attendance_player_idx
  on public.match_attendance(season_player_id);

alter table public.match_attendance enable row level security;
drop policy if exists match_attendance_read on public.match_attendance;
create policy match_attendance_read on public.match_attendance
  for select to authenticated using (true);
grant select on public.match_attendance to authenticated;

-- Feuille de match : l'admin fixe la liste des présents (remplace l'existante).
create or replace function public.staff_set_match_attendance(
  p_match_id uuid,
  p_present uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_season_id uuid;
  v_player uuid;
  v_profiles uuid[];
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select season_id into v_season_id from public.matches where id = p_match_id;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  -- Profils concernés avant/après (pour recalcul des badges).
  select array_agg(distinct sp.profile_id)
  into v_profiles
  from public.match_attendance ma
  join public.season_players sp on sp.id = ma.season_player_id
  where ma.match_id = p_match_id and sp.profile_id is not null;

  delete from public.match_attendance where match_id = p_match_id;

  if p_present is not null then
    foreach v_player in array p_present loop
      if not exists (
        select 1 from public.season_players sp
        where sp.id = v_player and sp.season_id = v_season_id and sp.is_active
      ) then
        raise exception 'Player is not active in the match season' using errcode = '22023';
      end if;
      insert into public.match_attendance(match_id, season_player_id)
      values (p_match_id, v_player)
      on conflict do nothing;
    end loop;
  end if;

  -- Recalcule les badges des profils avant + après.
  select array_cat(coalesce(v_profiles, '{}'), coalesce(array_agg(distinct sp.profile_id), '{}'))
  into v_profiles
  from public.season_players sp
  where sp.id = any (coalesce(p_present, '{}')) and sp.profile_id is not null;

  if v_profiles is not null then
    foreach v_player in array v_profiles loop
      perform public.recalculate_profile_badges(v_player);
    end loop;
  end if;

  return true;
end;
$function$;

-- Appearances = matchs terminés où le joueur est présent (feuille de match) OU
-- a une stat (buteur / clean sheet). Mise à jour du moteur de badges.
create or replace function public.recalculate_profile_badges(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_goals integer := 0;
  v_cs integer := 0;
  v_apps integer := 0;
  v_maxmatch integer := 0;
  v_preds integer := 0;
  v_exacts integer := 0;
  v_bets integer := 0;
  b record;
  v_earned boolean;
begin
  if p_profile_id is null then
    return;
  end if;

  with sp as (
    select id from public.season_players where profile_id = p_profile_id
  ), mps as (
    select s.match_id, s.goals, s.clean_sheet
    from public.match_player_stats s
    join sp on sp.id = s.season_player_id
    join public.matches m on m.id = s.match_id
      and m.status in ('termine', 'archive')
  ), apps as (
    select distinct match_id from (
      select ma.match_id
      from public.match_attendance ma
      join sp on sp.id = ma.season_player_id
      join public.matches m on m.id = ma.match_id
        and m.status in ('termine', 'archive')
      union
      select match_id from mps
    ) u
  )
  select
    coalesce((select sum(goals) from mps), 0),
    coalesce((select count(*) from mps where clean_sheet), 0),
    coalesce((select count(*) from apps), 0),
    coalesce((select max(goals) from mps), 0)
  into v_goals, v_cs, v_apps, v_maxmatch;

  select coalesce(count(*) filter (where is_filled), 0)
  into v_preds
  from public.match_predictions where profile_id = p_profile_id;

  select coalesce(sum(bon_pari), 0), coalesce(sum(exact), 0)
  into v_bets, v_exacts
  from public.v_match_prediction_flags where profile_id = p_profile_id;

  for b in select id, metric, threshold from public.badges where auto loop
    v_earned := case b.metric
      when 'goals'        then v_goals >= b.threshold
      when 'clean_sheets' then v_cs >= b.threshold
      when 'appearances'  then v_apps >= b.threshold
      when 'match_goals'  then v_maxmatch >= b.threshold
      when 'predictions'  then v_preds >= b.threshold
      when 'exact_scores' then v_exacts >= b.threshold
      when 'good_bets'    then v_bets >= b.threshold
      else false
    end;

    if v_earned then
      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing;
    else
      delete from public.profile_badges
      where profile_id = p_profile_id and badge_id = b.id and source = 'auto';
    end if;
  end loop;
end;
$function$;

-- Recalcul badges quand la feuille de match change.
create or replace function public.trg_badges_on_attendance()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_profile uuid;
begin
  select sp.profile_id into v_profile
  from public.season_players sp
  where sp.id = coalesce(new.season_player_id, old.season_player_id);
  if v_profile is not null then
    perform public.recalculate_profile_badges(v_profile);
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_badges_attendance on public.match_attendance;
create trigger trg_badges_attendance
  after insert or delete on public.match_attendance
  for each row execute function public.trg_badges_on_attendance();

-- Attribution / retrait manuel d'un badge par l'admin.
create or replace function public.staff_award_badge(
  p_profile_id uuid,
  p_badge_code text
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_badge_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  select id into v_badge_id from public.badges where code = p_badge_code;
  if not found then
    raise exception 'Unknown badge' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'Unknown profile' using errcode = '22023';
  end if;
  insert into public.profile_badges(profile_id, badge_id, source, awarded_by)
  values (p_profile_id, v_badge_id, 'manual', auth.uid())
  on conflict (profile_id, badge_id)
  do update set source = 'manual', awarded_by = auth.uid(), awarded_at = now();
  return true;
end;
$function$;

create or replace function public.staff_revoke_badge(
  p_profile_id uuid,
  p_badge_code text
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_badge_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  select id into v_badge_id from public.badges where code = p_badge_code;
  if not found then
    raise exception 'Unknown badge' using errcode = '22023';
  end if;
  delete from public.profile_badges
  where profile_id = p_profile_id and badge_id = v_badge_id;
  -- Un badge auto encore mérité sera réattribué au prochain recalcul.
  perform public.recalculate_profile_badges(p_profile_id);
  return true;
end;
$function$;

revoke all on function public.staff_set_match_attendance(uuid, uuid[]) from public, anon;
revoke all on function public.staff_award_badge(uuid, text) from public, anon;
revoke all on function public.staff_revoke_badge(uuid, text) from public, anon;
grant execute on function public.staff_set_match_attendance(uuid, uuid[]) to authenticated;
grant execute on function public.staff_award_badge(uuid, text) to authenticated;
grant execute on function public.staff_revoke_badge(uuid, text) to authenticated;
