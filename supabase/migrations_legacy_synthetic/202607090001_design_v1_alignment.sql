begin;

create or replace function public.current_profile_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_profile_role() = 'admin', false);
$$;

create or replace function public.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_profile_role() = 'moderateur', false);
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.seed_match_predictions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled
  )
  select new.id, p.id, 0, 0, false
  from public.profiles p
  where p.status = 'active'
  on conflict (match_id, profile_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_match_predictions on public.matches;
create trigger trg_seed_match_predictions
after insert on public.matches
for each row execute function public.seed_match_predictions();

create or replace function public.seed_season_predictions_for_player()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.season_predictions (
    season_id,
    predictor_profile_id,
    player_profile_id,
    category,
    predicted_value_20,
    is_filled
  )
  select
    new.season_id,
    predictor.id,
    new.profile_id,
    category,
    0,
    false
  from public.profiles predictor
  cross join lateral unnest(
    case
      when new.is_goalkeeper_snapshot then array['clean_sheets']::text[]
      else array['buts','passes','hommes_du_match']::text[]
    end
  ) as category
  where predictor.status = 'active'
  on conflict (
    season_id,
    predictor_profile_id,
    player_profile_id,
    category
  ) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_season_predictions_for_player on public.season_players;
create trigger trg_seed_season_predictions_for_player
after insert on public.season_players
for each row execute function public.seed_season_predictions_for_player();

create or replace function public.seed_predictions_for_new_active_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
  select m.id, new.id, 0, 0, false
  from public.matches m
  where m.status = 'a_venir'
  on conflict (match_id, profile_id) do nothing;

  insert into public.season_predictions (
    season_id,
    predictor_profile_id,
    player_profile_id,
    category,
    predicted_value_20,
    is_filled
  )
  select
    sp.season_id,
    new.id,
    sp.profile_id,
    category,
    0,
    false
  from public.season_players sp
  cross join lateral unnest(
    case
      when sp.is_goalkeeper_snapshot then array['clean_sheets']::text[]
      else array['buts','passes','hommes_du_match']::text[]
    end
  ) as category
  join public.seasons s on s.id = sp.season_id and s.status = 'open'
  on conflict (
    season_id,
    predictor_profile_id,
    player_profile_id,
    category
  ) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_seed_predictions_for_new_active_profile on public.profiles;
create trigger trg_seed_predictions_for_new_active_profile
after insert or update of status on public.profiles
for each row execute function public.seed_predictions_for_new_active_profile();

create or replace function public.claim_live_control(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  if not public.is_admin() then
    raise exception 'Admin role required';
  end if;

  update public.live_sessions
  set
    controller_profile_id = auth.uid(),
    controller_session_id = p_controller_session_id,
    controller_disconnected_at = null,
    updated_at = now()
  where match_id = p_match_id
    and controller_profile_id is null
    and controller_session_id is null;

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.update_live_status(
  p_match_id uuid,
  p_controller_session_id text,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  if p_status not in ('not_started','running','paused','halftime','finished') then
    raise exception 'Invalid live status';
  end if;

  update public.live_sessions
  set
    elapsed_seconds = case
      when status = 'running' and clock_started_at is not null then
        elapsed_seconds + greatest(0, floor(extract(epoch from (now() - clock_started_at)))::integer)
      else elapsed_seconds
    end,
    status = p_status,
    clock_started_at = case when p_status = 'running' then now() else null end,
    updated_at = now()
  where match_id = p_match_id
    and controller_profile_id = auth.uid()
    and controller_session_id = p_controller_session_id;

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.release_live_control(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  update public.live_sessions
  set
    controller_profile_id = null,
    controller_session_id = null,
    controller_disconnected_at = null,
    updated_at = now()
  where match_id = p_match_id
    and controller_profile_id = auth.uid()
    and controller_session_id = p_controller_session_id;

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.force_resume_live(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required';
  end if;

  update public.live_sessions
  set
    controller_profile_id = auth.uid(),
    controller_session_id = p_controller_session_id,
    controller_disconnected_at = null,
    updated_at = now()
  where match_id = p_match_id
    and controller_disconnected_at is not null
    and controller_disconnected_at <= now() - interval '60 seconds';

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create unique index if not exists uq_match_motm_match
on public.match_motm(match_id);

create or replace view public.v_match_prediction_points as
select
  mp.id,
  mp.match_id,
  mp.profile_id,
  case
    when not mp.is_filled then 0::numeric
    when m.score_as_grinta is null or m.score_adverse is null then 0::numeric
    when sign(mp.predicted_score_as_grinta - mp.predicted_score_adverse)
       <> sign(m.score_as_grinta - m.score_adverse) then 0::numeric
    else
      case
        when m.score_as_grinta > m.score_adverse then mo.odds_victoire_as_grinta
        when m.score_as_grinta = m.score_adverse then mo.odds_nul
        else mo.odds_victoire_adverse
      end
      * case
          when mp.predicted_score_as_grinta = m.score_as_grinta
           and mp.predicted_score_adverse = m.score_adverse then 15
          else 10
        end
  end as points
from public.match_predictions mp
join public.matches m on m.id = mp.match_id
left join public.match_odds mo on mo.match_id = m.id;

create or replace view public.v_player_season_stats as
with appearances as (
  select
    m.season_id,
    mp.profile_id,
    count(distinct mp.match_id)::integer as matches_played
  from public.match_participants mp
  join public.matches m on m.id = mp.match_id
  where m.status in ('termine','archive')
  group by m.season_id, mp.profile_id
),
goal_stats as (
  select
    m.season_id,
    g.scorer_profile_id as profile_id,
    count(*) filter (where g.team = 'as_grinta' and g.scorer_profile_id is not null)::integer as goals
  from public.goals g
  join public.matches m on m.id = g.match_id
  where m.status in ('termine','archive')
  group by m.season_id, g.scorer_profile_id
),
assist_stats as (
  select
    m.season_id,
    g.assist_profile_id as profile_id,
    count(*) filter (where g.team = 'as_grinta' and g.assist_profile_id is not null)::integer as assists
  from public.goals g
  join public.matches m on m.id = g.match_id
  where m.status in ('termine','archive')
  group by m.season_id, g.assist_profile_id
),
motm_stats as (
  select
    m.season_id,
    mm.profile_id,
    count(*)::integer as motm
  from public.match_motm mm
  join public.matches m on m.id = mm.match_id
  group by m.season_id, mm.profile_id
),
clean_sheet_stats as (
  select
    m.season_id,
    mp.profile_id,
    count(*) filter (where m.score_adverse = 0)::integer as clean_sheets
  from public.match_participants mp
  join public.matches m on m.id = mp.match_id
  join public.season_players sp
    on sp.season_id = m.season_id
   and sp.profile_id = mp.profile_id
   and sp.is_goalkeeper_snapshot
  where m.status in ('termine','archive')
  group by m.season_id, mp.profile_id
)
select
  sp.season_id,
  sp.profile_id,
  coalesce(a.matches_played, 0) as matches_played,
  coalesce(g.goals, 0) as goals,
  coalesce(ast.assists, 0) as assists,
  coalesce(mm.motm, 0) as motm,
  coalesce(cs.clean_sheets, 0) as clean_sheets
from public.season_players sp
left join appearances a using (season_id, profile_id)
left join goal_stats g using (season_id, profile_id)
left join assist_stats ast using (season_id, profile_id)
left join motm_stats mm using (season_id, profile_id)
left join clean_sheet_stats cs using (season_id, profile_id);

create or replace view public.v_player_career_stats as
select
  profile_id,
  sum(matches_played)::integer as matches_played,
  sum(goals)::integer as goals,
  sum(assists)::integer as assists,
  sum(motm)::integer as motm,
  sum(clean_sheets)::integer as clean_sheets
from public.v_player_season_stats
group by profile_id;

create or replace view public.v_season_prediction_points as
select
  sp.id,
  sp.season_id,
  sp.predictor_profile_id,
  sp.player_profile_id,
  sp.category,
  case
    when not sp.is_filled then 0
    when stats.matches_played = 0 then 0
    else round(
      greatest(
        0,
        1 - abs(
          case sp.category
            when 'buts' then stats.goals
            when 'passes' then stats.assists
            when 'hommes_du_match' then stats.motm
            when 'clean_sheets' then stats.clean_sheets
            else 0
          end
          - (sp.predicted_value_20 * stats.matches_played / 20.0)
        ) / greatest(sp.predicted_value_20 * stats.matches_played / 20.0, 1)
      ) * 20
    )::integer
  end as points
from public.season_predictions sp
join public.v_player_season_stats stats
  on stats.season_id = sp.season_id
 and stats.profile_id = sp.player_profile_id;

create or replace view public.v_classement_general as
with match_totals as (
  select profile_id, coalesce(sum(points), 0)::numeric as match_points
  from public.v_match_prediction_points
  group by profile_id
),
season_totals as (
  select predictor_profile_id as profile_id,
         coalesce(sum(points), 0)::numeric as season_points
  from public.v_season_prediction_points
  group by predictor_profile_id
)
select
  p.id as profile_id,
  p.first_name,
  p.last_name,
  coalesce(mt.match_points, 0) as match_points,
  coalesce(st.season_points, 0) as season_points,
  coalesce(mt.match_points, 0) + coalesce(st.season_points, 0) as total_points
from public.profiles p
left join match_totals mt on mt.profile_id = p.id
left join season_totals st on st.profile_id = p.id
where p.status = 'active';

alter table public.profiles enable row level security;
alter table public.seasons enable row level security;
alter table public.season_players enable row level security;
alter table public.opponents enable row level security;
alter table public.matches enable row level security;
alter table public.match_participants enable row level security;
alter table public.live_sessions enable row level security;
alter table public.live_positions enable row level security;
alter table public.goals enable row level security;
alter table public.substitutions enable row level security;
alter table public.match_motm enable row level security;
alter table public.match_predictions enable row level security;
alter table public.season_predictions enable row level security;
alter table public.match_odds enable row level security;
alter table public.formations enable row level security;

commit;
