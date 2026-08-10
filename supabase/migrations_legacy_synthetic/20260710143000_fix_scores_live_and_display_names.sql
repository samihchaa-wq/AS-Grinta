drop trigger if exists goals_recalculate_match_score on public.goals;
drop function if exists public.recalculate_match_score_from_goals();

create or replace function public.assert_coach_event_allowed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_status text;
  running boolean;
begin
  select m.status::text,
         coalesce(s.is_running, false)
  into current_status, running
  from public.matches m
  left join public.coach_match_sessions s on s.match_id = m.id
  where m.id = new.match_id;

  if current_status is null then
    raise exception 'Match introuvable';
  end if;

  if current_status <> 'en_cours' or not running then
    raise exception 'Les événements ne peuvent être ajoutés qu’après le démarrage du match';
  end if;

  return new;
end;
$$;

drop trigger if exists coach_match_events_match_open_guard
  on public.coach_match_events;
create trigger coach_match_events_match_open_guard
before insert or update on public.coach_match_events
for each row execute function public.assert_coach_event_allowed();

create or replace function public.start_coach_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;

  update public.matches
  set status = 'en_cours', updated_at = now()
  where id = p_match_id and status in ('a_venir', 'en_cours');

  if not found then
    raise exception 'Ce match ne peut pas être démarré';
  end if;

  update public.coach_match_sessions
  set is_running = true,
      updated_by = auth.uid(),
      updated_at = now()
  where match_id = p_match_id;

  return true;
end;
$$;

revoke all on function public.start_coach_match(uuid) from public, anon;
grant execute on function public.start_coach_match(uuid) to authenticated;

create or replace function public.finish_coach_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  session_score_us integer;
  session_score_them integer;
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;

  select score_as_grinta, score_adverse
  into session_score_us, session_score_them
  from public.coach_match_sessions
  where match_id = p_match_id
  for update;

  update public.coach_match_sessions
  set is_running = false,
      updated_by = auth.uid(),
      updated_at = now()
  where match_id = p_match_id;

  update public.matches
  set status = 'termine',
      score_as_grinta = coalesce(session_score_us, score_as_grinta, 0),
      score_adverse = coalesce(session_score_them, score_adverse, 0),
      updated_at = now()
  where id = p_match_id and status in ('a_venir', 'en_cours');

  return found;
end;
$$;

revoke all on function public.finish_coach_match(uuid) from public, anon;
grant execute on function public.finish_coach_match(uuid) to authenticated;

create or replace view public.v_classement_general as
with mt as (
  select profile_id, coalesce(sum(points), 0::numeric) as match_points
  from public.v_match_prediction_points
  group by profile_id
), st as (
  select predictor_profile_id as profile_id,
         coalesce(sum(points), 0::bigint)::numeric as season_points
  from public.v_season_prediction_points
  group by predictor_profile_id
), match_max as (
  select coalesce(sum(
    case
      when m.score_as_grinta > m.score_adverse then mo.odds_victoire_as_grinta
      when m.score_as_grinta = m.score_adverse then mo.odds_nul
      else mo.odds_victoire_adverse
    end * 15::numeric
  ), 0::numeric) as max_points
  from public.matches m
  join public.match_odds mo on mo.match_id = m.id
  where m.status in ('termine', 'archive')
    and m.score_as_grinta is not null
    and m.score_adverse is not null
), season_expected as (
  select sp.predictor_profile_id as profile_id,
         count(*)::numeric * 20::numeric as max_points
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  left join public.v_player_season_stats stats
    on stats.season_id = sp.season_id
   and stats.profile_id = sp.player_profile_id
  where not (s.status = 'archived' and coalesce(stats.matches_played, 0) < 3)
  group by sp.predictor_profile_id
)
select p.id as profile_id,
       p.first_name,
       p.last_name,
       coalesce(mt.match_points, 0::numeric) as match_points,
       coalesce(st.season_points, 0::numeric) as season_points,
       coalesce(mt.match_points, 0::numeric) + coalesce(st.season_points, 0::numeric) as total_points,
       mm.max_points as match_max_points,
       coalesce(se.max_points, 0::numeric) as season_max_points,
       case when mm.max_points > 0 then round(100::numeric * coalesce(mt.match_points, 0::numeric) / mm.max_points, 2) else 0::numeric end as match_percentage,
       case when coalesce(se.max_points, 0::numeric) > 0 then round(100::numeric * coalesce(st.season_points, 0::numeric) / se.max_points, 2) else 0::numeric end as season_percentage,
       p.surnom
from public.profiles p
cross join match_max mm
left join mt on mt.profile_id = p.id
left join st on st.profile_id = p.id
left join season_expected se on se.profile_id = p.id
where p.status = 'active';
