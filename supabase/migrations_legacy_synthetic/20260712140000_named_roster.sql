-- Effectif nommé : season_players devient une liste de joueurs (prénom, nom,
-- gardien), SANS compte. Les buteurs, clean sheets et pronostics de saison
-- portent sur ces joueurs, totalement distincts des pronostiqueurs (profiles).
-- (Aucune donnée réelle : match_player_stats vide, season_predictions de test.)

drop view if exists public.v_classement_general cascade;
drop view if exists public.v_season_prediction_bonus cascade;
drop view if exists public.v_season_prediction_points cascade;
drop view if exists public.v_scorer_standings cascade;
drop view if exists public.v_season_match_count cascade;
drop view if exists public.v_player_season_stats cascade;
drop function if exists public.finalize_match_postgame(uuid, integer, jsonb, uuid);

delete from public.season_predictions;
delete from public.match_player_stats;
delete from public.season_players;

-- season_players : joueurs nommés
alter table public.season_players drop column profile_id cascade;
alter table public.season_players
  rename column is_goalkeeper_snapshot to is_goalkeeper;
alter table public.season_players
  add column first_name text not null,
  add column last_name text not null,
  add column is_active boolean not null default true;

-- match_player_stats -> joueur de l'effectif
alter table public.match_player_stats drop column profile_id cascade;
alter table public.match_player_stats
  add column season_player_id uuid
    references public.season_players(id) on delete cascade;
create unique index match_player_stats_match_player_uidx
  on public.match_player_stats(match_id, season_player_id);

-- season_predictions -> joueur de l'effectif
alter table public.season_predictions drop column player_profile_id cascade;
alter table public.season_predictions
  add column season_player_id uuid
    references public.season_players(id) on delete cascade;
alter table public.season_predictions
  drop constraint if exists season_predictions_category_check;
alter table public.season_predictions
  add constraint season_predictions_category_check
    check (category in ('buts', 'clean_sheets'));
create unique index season_predictions_unique_idx
  on public.season_predictions(
    season_id, predictor_profile_id, season_player_id, category);

-- Validation du match : score adverse + buteurs + clean sheet du gardien.
create or replace function public.finalize_match_postgame(
  p_match_id uuid,
  p_score_adverse integer,
  p_scorers jsonb,
  p_clean_sheet_player_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  item jsonb;
  match_season_id uuid;
  pid uuid;
  g integer;
  total_goals integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin role required';
  end if;
  if p_score_adverse < 0 then
    raise exception 'Score adverse invalide';
  end if;

  select season_id into match_season_id
  from public.matches
  where id = p_match_id and status in ('a_venir', 'termine')
  for update;
  if match_season_id is null then
    raise exception 'Only upcoming or finished matches can be validated';
  end if;

  if jsonb_typeof(coalesce(p_scorers, '[]'::jsonb)) <> 'array' then
    raise exception 'Invalid scorers payload';
  end if;

  for item in
    select * from jsonb_array_elements(coalesce(p_scorers, '[]'::jsonb))
  loop
    pid := nullif(item->>'season_player_id', '')::uuid;
    g := coalesce((item->>'goals')::integer, 0);
    if pid is null then
      raise exception 'Invalid scorer identifier';
    end if;
    if g < 0 then
      raise exception 'Negative goals are not allowed';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.id = pid and sp.season_id = match_season_id
    ) then
      raise exception 'Scorer is not in the season squad';
    end if;
    total_goals := total_goals + g;
  end loop;

  if p_clean_sheet_player_id is not null then
    if p_score_adverse > 0 then
      raise exception 'Clean sheet is impossible when the opponent scored';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.id = p_clean_sheet_player_id
        and sp.season_id = match_season_id
        and sp.is_goalkeeper
    ) then
      raise exception 'Clean sheet must go to a goalkeeper of the squad';
    end if;
  end if;

  delete from public.match_player_stats where match_id = p_match_id;

  insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
  select p_match_id, s.season_player_id, s.goals, false
  from (
    select nullif(e->>'season_player_id', '')::uuid as season_player_id,
           sum(coalesce((e->>'goals')::integer, 0)) as goals
    from jsonb_array_elements(coalesce(p_scorers, '[]'::jsonb)) e
    group by 1
  ) s
  where s.goals > 0;

  if p_clean_sheet_player_id is not null then
    insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
    values (p_match_id, p_clean_sheet_player_id, 0, true)
    on conflict (match_id, season_player_id) do update set clean_sheet = true;
  end if;

  update public.matches
  set score_as_grinta = total_goals,
      score_adverse = p_score_adverse,
      status = 'termine',
      result_validated_at = now(),
      updated_at = now()
  where id = p_match_id and status in ('a_venir', 'termine');

  return found;
end;
$$;

grant execute on function
  public.finalize_match_postgame(uuid, integer, jsonb, uuid) to authenticated;

-- Semences : un pronostic de saison par pronostiqueur actif et par joueur.
create or replace function public.seed_season_predictions_for_player()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  insert into public.season_predictions(
    season_id, predictor_profile_id, season_player_id, category,
    predicted_value_30, is_filled
  )
  select new.season_id, p.id, new.id,
    case when new.is_goalkeeper then 'clean_sheets' else 'buts' end, 0, false
  from public.profiles p
  where p.status = 'active'
  on conflict(season_id, predictor_profile_id, season_player_id, category)
    do nothing;
  return new;
end;
$$;

create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.status <> 'active' then return new; end if;

  insert into public.match_predictions(
    match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse,
    is_filled
  )
  select id, new.id, 0, 0, false
  from public.matches
  where status = 'a_venir'
  on conflict(match_id, profile_id) do nothing;

  insert into public.season_predictions(
    season_id, predictor_profile_id, season_player_id, category,
    predicted_value_30, is_filled
  )
  select sp.season_id, new.id, sp.id,
    case when sp.is_goalkeeper then 'clean_sheets' else 'buts' end, 0, false
  from public.season_players sp
  join public.seasons s on s.id = sp.season_id and s.status = 'open'
  where sp.is_active
  on conflict(season_id, predictor_profile_id, season_player_id, category)
    do nothing;
  return new;
end;
$$;

create or replace function public.validate_season_prediction_category()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare goalkeeper boolean;
begin
  select is_goalkeeper into goalkeeper
  from public.season_players
  where id = new.season_player_id and season_id = new.season_id;

  if goalkeeper is null then
    raise exception 'Player is not in the season squad';
  end if;
  if goalkeeper and new.category <> 'clean_sheets' then
    raise exception 'A goalkeeper is only predicted on clean sheets';
  end if;
  if not goalkeeper and new.category <> 'buts' then
    raise exception 'An outfield player is only predicted on goals';
  end if;
  return new;
end;
$$;

-- Vues (buts + clean sheets par joueur de l'effectif)
create view public.v_player_season_stats with (security_invoker = true) as
select
  sp.season_id, sp.id as season_player_id, sp.first_name, sp.last_name,
  sp.is_goalkeeper, sp.is_active,
  coalesce((
    select sum(s.goals)::int
    from public.match_player_stats s
    join public.matches m on m.id = s.match_id
    where s.season_player_id = sp.id and m.status in ('termine', 'archive')
  ), 0) as goals,
  coalesce((
    select count(*)::int
    from public.match_player_stats s
    join public.matches m on m.id = s.match_id
    where s.season_player_id = sp.id and s.clean_sheet
      and m.status in ('termine', 'archive')
  ), 0) as clean_sheets
from public.season_players sp;

create view public.v_scorer_standings with (security_invoker = true) as
select season_id, season_player_id, first_name, last_name,
       is_goalkeeper, goals, clean_sheets
from public.v_player_season_stats
where is_active;

create view public.v_season_match_count with (security_invoker = true) as
select season_id, count(*)::int as matches_played
from public.matches
where status in ('termine', 'archive') and score_as_grinta is not null
group by season_id;

create view public.v_season_prediction_points with (security_invoker = true) as
with base as (
  select
    sp.id, sp.season_id, sp.predictor_profile_id, sp.season_player_id,
    sp.category, sp.predicted_value_30,
    case sp.category
      when 'buts' then st.goals
      when 'clean_sheets' then st.clean_sheets
      else 0
    end as metric,
    s.status as season_status,
    mc.matches_played
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_player_id = sp.season_player_id
  left join public.v_season_match_count mc on mc.season_id = sp.season_id
  where sp.is_filled and sp.category in ('buts', 'clean_sheets')
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
),
targeted as (
  select *,
    case
      when season_status = 'archived' then metric::numeric
      when coalesce(matches_played, 0) > 0
        then round(metric::numeric * 30.0 / matches_played)
      else null
    end as target
  from base
)
select
  id, season_id, predictor_profile_id, season_player_id, category,
  (count(*) over (
      partition by season_id, season_player_id, category)
   - (rank() over (
      partition by season_id, season_player_id, category
      order by abs(predicted_value_30 - target)) - 1))::int as points
from targeted
where target is not null;

create view public.v_season_prediction_bonus with (security_invoker = true) as
with target_goals as (
  select
    sp.season_id, sp.season_player_id,
    case
      when s.status = 'archived' then st.goals::numeric
      when coalesce(mc.matches_played, 0) > 0
        then round(st.goals::numeric * 30.0 / mc.matches_played)
      else null
    end as target
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_player_id = sp.season_player_id
  left join public.v_season_match_count mc on mc.season_id = sp.season_id
  where sp.category = 'buts'
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
  group by sp.season_id, sp.season_player_id, target
),
actual_rank as (
  select season_id, season_player_id,
    rank() over (partition by season_id order by target desc) as actual_rank
  from target_goals
  where target is not null
),
pred_rank as (
  select sp.season_id, sp.predictor_profile_id, sp.season_player_id,
    rank() over (
      partition by sp.season_id, sp.predictor_profile_id
      order by sp.predicted_value_30 desc) as pred_rank
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  where sp.category = 'buts' and sp.is_filled
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
)
select
  pr.season_id, pr.predictor_profile_id,
  sum(
    case
      when pr.pred_rank = ar.actual_rank then 2
      when ceil(least(pr.pred_rank, 15) / 5.0)
         = ceil(least(ar.actual_rank, 15) / 5.0) then 1
      else 0
    end
  )::int as bonus_points
from pred_rank pr
join actual_rank ar
  on ar.season_id = pr.season_id
  and ar.season_player_id = pr.season_player_id
group by pr.season_id, pr.predictor_profile_id;

create view public.v_classement_general with (security_invoker = true) as
with mt as (
  select profile_id, coalesce(sum(points), 0)::numeric as match_points
  from public.v_match_prediction_points group by profile_id
),
sp as (
  select predictor_profile_id as profile_id,
         coalesce(sum(points), 0)::numeric as season_points
  from public.v_season_prediction_points group by predictor_profile_id
),
bn as (
  select predictor_profile_id as profile_id,
         coalesce(sum(bonus_points), 0)::numeric as bonus_points
  from public.v_season_prediction_bonus group by predictor_profile_id
),
tot as (
  select p.id as profile_id, p.first_name, p.surnom,
    coalesce(mt.match_points, 0) as match_points,
    coalesce(sp.season_points, 0) + coalesce(bn.bonus_points, 0) as season_points
  from public.profiles p
  left join mt on mt.profile_id = p.id
  left join sp on sp.profile_id = p.id
  left join bn on bn.profile_id = p.id
  where p.status = 'active'
),
mx as (
  select max(match_points) as mm, max(season_points) as ms from tot
)
select
  t.profile_id, t.first_name, t.surnom,
  t.match_points, t.season_points,
  round(
    70 * (case when mx.mm > 0 then t.match_points / mx.mm else 0 end)
    + 30 * (case when mx.ms > 0 then t.season_points / mx.ms else 0 end),
  2) as total_points
from tot t cross join mx;
