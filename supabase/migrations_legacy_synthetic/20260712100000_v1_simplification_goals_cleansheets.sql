-- =====================================================================
-- V1 — Simplification radicale : l'application ne gère plus que
--   ⚽ les buts  et  🧤 les clean sheets de Samih (gardien).
-- Suppression de : passes décisives, homme du match, penalties provoqués,
-- présence/absence, invités, compositions. Les vues de statistiques et de
-- pronostics de saison sont refondues autour de ces deux seules données.
-- (Aucune donnée réelle : match_player_stats/motm/invités/participants
--  sont vides ; les 3 pronos de saison sont des données de test.)
-- =====================================================================

-- 1) Vues dépendantes retirées (reconstruites plus bas).
drop view if exists public.v_classement_general cascade;
drop view if exists public.v_season_prediction_points cascade;
drop view if exists public.v_player_career_stats cascade;
drop view if exists public.v_player_season_stats cascade;
drop view if exists public.v_scorer_standings cascade;
drop view if exists public.v_season_match_count cascade;
drop view if exists public.v_season_prediction_bonus cascade;

-- 2) Tables et fonctions mortes (fonctionnalités supprimées, 0 ligne).
drop function if exists public.claim_player_profile(uuid) cascade;
drop function if exists public.staff_list_players() cascade;
drop table if exists public.match_motm cascade;
drop table if exists public.match_guest_stats cascade;
drop table if exists public.match_participants cascade;
drop table if exists public.players cascade;

-- 3) match_player_stats réduit à buts + clean sheet.
alter table public.match_player_stats
  drop column if exists present,
  drop column if exists assists,
  drop column if exists penalty_faults;
alter table public.match_player_stats
  alter column goals set default 0,
  alter column clean_sheet set default false;

-- 4) Pronostics de saison : uniquement 'buts' et 'clean_sheets'.
delete from public.season_predictions where category not in ('buts', 'clean_sheets');

create or replace function public.validate_season_prediction_category()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare goalkeeper boolean;
begin
  select is_goalkeeper_snapshot into goalkeeper
  from public.season_players
  where season_id = new.season_id and profile_id = new.player_profile_id;

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

create or replace function public.seed_season_predictions_for_player()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  insert into public.season_predictions(
    season_id, predictor_profile_id, player_profile_id, category,
    predicted_value_30, is_filled
  )
  select new.season_id, p.id, new.profile_id,
    case when new.is_goalkeeper_snapshot then 'clean_sheets' else 'buts' end,
    0, false
  from public.profiles p
  where p.status = 'active'
  on conflict(season_id, predictor_profile_id, player_profile_id, category)
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
    season_id, predictor_profile_id, player_profile_id, category,
    predicted_value_30, is_filled
  )
  select sp.season_id, new.id, sp.profile_id,
    case when sp.is_goalkeeper_snapshot then 'clean_sheets' else 'buts' end,
    0, false
  from public.season_players sp
  join public.seasons s on s.id = sp.season_id and s.status = 'open'
  on conflict(season_id, predictor_profile_id, player_profile_id, category)
    do nothing;
  return new;
end;
$$;

-- 5) Validation d'un match : score adverse + liste de buteurs + clean sheet.
--    Le score d'AS Grinta est la somme des buts saisis.
drop function if exists public.finalize_match_postgame(
  uuid, integer, integer, uuid, jsonb, jsonb);

create or replace function public.finalize_match_postgame(
  p_match_id uuid,
  p_score_adverse integer,
  p_scorers jsonb,
  p_clean_sheet_profile_id uuid default null
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
    pid := nullif(item->>'profile_id', '')::uuid;
    g := coalesce((item->>'goals')::integer, 0);
    if pid is null then
      raise exception 'Invalid scorer identifier';
    end if;
    if g < 0 then
      raise exception 'Negative goals are not allowed';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.season_id = match_season_id and sp.profile_id = pid
    ) then
      raise exception 'Scorer is not in the season squad';
    end if;
    total_goals := total_goals + g;
  end loop;

  if p_clean_sheet_profile_id is not null then
    if p_score_adverse > 0 then
      raise exception 'Clean sheet is impossible when the opponent scored';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.season_id = match_season_id
        and sp.profile_id = p_clean_sheet_profile_id
        and sp.is_goalkeeper_snapshot
    ) then
      raise exception 'Clean sheet must go to a goalkeeper of the squad';
    end if;
  end if;

  delete from public.match_player_stats where match_id = p_match_id;

  insert into public.match_player_stats(match_id, profile_id, goals, clean_sheet)
  select p_match_id, s.profile_id, s.goals, false
  from (
    select nullif(e->>'profile_id', '')::uuid as profile_id,
           sum(coalesce((e->>'goals')::integer, 0)) as goals
    from jsonb_array_elements(coalesce(p_scorers, '[]'::jsonb)) e
    group by 1
  ) s
  where s.goals > 0;

  if p_clean_sheet_profile_id is not null then
    insert into public.match_player_stats(match_id, profile_id, goals, clean_sheet)
    values (p_match_id, p_clean_sheet_profile_id, 0, true)
    on conflict (match_id, profile_id) do update set clean_sheet = true;
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

-- 6) Totaux réels par saison / joueur (buts + clean sheets).
create view public.v_player_season_stats as
select
  sp.season_id,
  sp.profile_id,
  sp.is_goalkeeper_snapshot as is_goalkeeper,
  coalesce((
    select sum(s.goals)::int
    from public.match_player_stats s
    join public.matches m on m.id = s.match_id
    where m.season_id = sp.season_id
      and s.profile_id = sp.profile_id
      and m.status in ('termine', 'archive')
  ), 0) as goals,
  coalesce((
    select count(*)::int
    from public.match_player_stats s
    join public.matches m on m.id = s.match_id
    where m.season_id = sp.season_id
      and s.profile_id = sp.profile_id
      and s.clean_sheet
      and m.status in ('termine', 'archive')
  ), 0) as clean_sheets
from public.season_players sp;

-- 7) Classement des buteurs (affichage) : joueurs actifs de chaque saison.
create view public.v_scorer_standings as
select st.season_id, st.profile_id, p.first_name, p.surnom,
       st.is_goalkeeper, st.goals, st.clean_sheets
from public.v_player_season_stats st
join public.profiles p on p.id = st.profile_id and p.status = 'active';

-- 8) Nombre de matchs validés par saison (base de la projection sur 30).
create view public.v_season_match_count as
select season_id, count(*)::int as matches_played
from public.matches
where status in ('termine', 'archive') and score_as_grinta is not null
group by season_id;

-- 9) Points des pronostics de saison : classement par proximité.
--    Cible = valeur réelle si saison archivée, sinon projection sur 30 matchs
--    (valeur réelle × 30 / nombre de matchs validés de la saison).
--    Points = nb participants − (nb de participants strictement plus proches).
create view public.v_season_prediction_points as
with base as (
  select
    sp.id, sp.season_id, sp.predictor_profile_id, sp.player_profile_id,
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
    on st.season_id = sp.season_id and st.profile_id = sp.player_profile_id
  left join public.v_season_match_count mc on mc.season_id = sp.season_id
  where sp.is_filled and sp.category in ('buts', 'clean_sheets')
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
  id, season_id, predictor_profile_id, player_profile_id, category,
  (count(*) over (
      partition by season_id, player_profile_id, category)
   - (rank() over (
      partition by season_id, player_profile_id, category
      order by abs(predicted_value_30 - target)) - 1))::int as points
from targeted
where target is not null;

-- 10) Bonus « classement prévisionnel des buteurs » (buts uniquement).
--     +2 si la place prédite d'un joueur = sa place réelle, +1 si même tiers
--     (1-5 / 6-10 / 11-15), 0 sinon.
create view public.v_season_prediction_bonus as
with target_goals as (
  select
    sp.season_id, sp.player_profile_id,
    case
      when s.status = 'archived' then st.goals::numeric
      when coalesce(mc.matches_played, 0) > 0
        then round(st.goals::numeric * 30.0 / mc.matches_played)
      else null
    end as target
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_id = sp.season_id and st.profile_id = sp.player_profile_id
  left join public.v_season_match_count mc on mc.season_id = sp.season_id
  where sp.category = 'buts'
  group by sp.season_id, sp.player_profile_id, target
),
actual_rank as (
  select season_id, player_profile_id,
    rank() over (partition by season_id order by target desc) as actual_rank
  from target_goals
  where target is not null
),
pred_rank as (
  select season_id, predictor_profile_id, player_profile_id,
    rank() over (
      partition by season_id, predictor_profile_id
      order by predicted_value_30 desc) as pred_rank
  from public.season_predictions
  where category = 'buts' and is_filled
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
  and ar.player_profile_id = pr.player_profile_id
group by pr.season_id, pr.predictor_profile_id;

-- 11) Classement général : 70 % pronostics de match, 30 % pronostics de
--     saison, chaque compétition normalisée sur son meilleur total.
create view public.v_classement_general as
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
