-- Homme du match (HDM) : désignation manuelle par match, plusieurs possibles.
-- Le badge « Homme du match » devient automatique dès 1 HDM ; le nombre de HDM
-- s'accumule (affichable en « ×N »).

create table if not exists public.match_man_of_match (
  match_id uuid not null references public.matches(id) on delete cascade,
  season_player_id uuid not null references public.season_players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (match_id, season_player_id)
);

create index if not exists match_mvp_player_idx
  on public.match_man_of_match(season_player_id);

alter table public.match_man_of_match enable row level security;
drop policy if exists match_mvp_read on public.match_man_of_match;
create policy match_mvp_read on public.match_man_of_match
  for select to authenticated using (true);
grant select on public.match_man_of_match to authenticated;

-- Le badge HDM passe en automatique (compteur de désignations).
update public.badges
set auto = true, metric = 'mvp', threshold = 1,
    description = 'Élu homme du match au moins une fois.'
where code = 'man_of_match';

-- Nombre de HDM d'une personne (pour l'affichage « ×N »).
create or replace function public.profile_mvp_count(p_profile_id uuid)
returns integer
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(count(*), 0)::integer
  from public.match_man_of_match mvp
  join public.season_players sp on sp.id = mvp.season_player_id
  join public.matches m on m.id = mvp.match_id
    and m.status in ('termine', 'archive')
  where sp.profile_id = p_profile_id;
$function$;

grant execute on function public.profile_mvp_count(uuid) to authenticated;

-- Saisie des HDM d'un match (remplace la liste existante).
create or replace function public.staff_set_match_mvp(
  p_match_id uuid,
  p_players uuid[]
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

revoke all on function public.staff_set_match_mvp(uuid, uuid[]) from public, anon;
grant execute on function public.staff_set_match_mvp(uuid, uuid[]) to authenticated;

-- Moteur de badges : ajoute la métrique « mvp » et compte les HDM dans les
-- présences (un HDM a forcément joué).
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
  v_mvp integer := 0;
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
  ), mvp as (
    select v.match_id
    from public.match_man_of_match v
    join sp on sp.id = v.season_player_id
    join public.matches m on m.id = v.match_id
      and m.status in ('termine', 'archive')
  ), apps as (
    select distinct match_id from (
      select ma.match_id
      from public.match_attendance ma
      join sp on sp.id = ma.season_player_id
      join public.matches m on m.id = ma.match_id
        and m.status in ('termine', 'archive')
      union select match_id from mps
      union select match_id from mvp
    ) u
  )
  select
    coalesce((select sum(goals) from mps), 0),
    coalesce((select count(*) from mps where clean_sheet), 0),
    coalesce((select count(*) from apps), 0),
    coalesce((select max(goals) from mps), 0),
    coalesce((select count(*) from mvp), 0)
  into v_goals, v_cs, v_apps, v_maxmatch, v_mvp;

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
      when 'mvp'          then v_mvp >= b.threshold
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

create or replace function public.trg_badges_on_mvp()
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

drop trigger if exists trg_badges_mvp on public.match_man_of_match;
create trigger trg_badges_mvp
  after insert or delete on public.match_man_of_match
  for each row execute function public.trg_badges_on_mvp();
