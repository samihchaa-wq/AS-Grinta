-- Post-match-only workflow: no composition or live coach board.
-- Adds permanent player match stats, temporary guest stats, penalty-fault tracking,
-- immediate prediction opening and automatic closing five minutes before kickoff.

create table if not exists public.match_player_stats (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  present boolean not null default false,
  goals integer not null default 0 check (goals >= 0),
  assists integer not null default 0 check (assists >= 0),
  penalty_faults integer not null default 0 check (penalty_faults >= 0),
  clean_sheet boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (match_id, profile_id)
);

create table if not exists public.match_guest_stats (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  display_name text not null check (btrim(display_name) <> ''),
  goals integer not null default 0 check (goals >= 0),
  assists integer not null default 0 check (assists >= 0),
  penalty_faults integer not null default 0 check (penalty_faults >= 0),
  created_at timestamptz not null default now()
);

alter table public.match_player_stats enable row level security;
alter table public.match_guest_stats enable row level security;

drop policy if exists match_player_stats_read on public.match_player_stats;
create policy match_player_stats_read on public.match_player_stats
for select to authenticated using (true);
drop policy if exists match_player_stats_staff_write on public.match_player_stats;
create policy match_player_stats_staff_write on public.match_player_stats
for all to authenticated using (public.is_match_staff()) with check (public.is_match_staff());

drop policy if exists match_guest_stats_read on public.match_guest_stats;
create policy match_guest_stats_read on public.match_guest_stats
for select to authenticated using (true);
drop policy if exists match_guest_stats_staff_write on public.match_guest_stats;
create policy match_guest_stats_staff_write on public.match_guest_stats
for all to authenticated using (public.is_match_staff()) with check (public.is_match_staff());

alter table public.season_predictions
  drop constraint if exists season_predictions_category_check;
alter table public.season_predictions
  add constraint season_predictions_category_check
  check (category = any(array[
    'buts','passes','hommes_du_match','clean_sheets','penalty_faults'
  ]));

create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  kickoff timestamptz;
  match_status text;
begin
  select ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris'), m.status
  into kickoff, match_status
  from public.matches m
  where m.id = new.match_id;

  if kickoff is null or match_status <> 'a_venir' or now() >= kickoff - interval '5 minutes' then
    raise exception 'Pronostic fermé';
  end if;

  new.profile_id := auth.uid();
  return new;
end;
$$;

drop trigger if exists match_predictions_window_guard on public.match_predictions;
create trigger match_predictions_window_guard
before insert or update on public.match_predictions
for each row execute function public.guard_match_prediction_window();

drop policy if exists match_predictions_owner_insert on public.match_predictions;
create policy match_predictions_owner_insert on public.match_predictions
for insert to authenticated
with check (
  profile_id = auth.uid() and exists (
    select 1 from public.matches m
    where m.id = match_predictions.match_id
      and m.status = 'a_venir'
      and now() < ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris') - interval '5 minutes'
  )
);

drop policy if exists match_predictions_owner_update_window on public.match_predictions;
create policy match_predictions_owner_update_window on public.match_predictions
for update to authenticated
using (profile_id = auth.uid())
with check (
  profile_id = auth.uid() and exists (
    select 1 from public.matches m
    where m.id = match_predictions.match_id
      and m.status = 'a_venir'
      and now() < ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris') - interval '5 minutes'
  )
);

-- Transactional post-match finalization.
create or replace function public.finalize_match_postgame(
  p_match_id uuid,
  p_score_grinta integer,
  p_score_adverse integer,
  p_motm_profile_id uuid,
  p_player_stats jsonb,
  p_guest_stats jsonb default '[]'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare item jsonb;
begin
  if not public.is_match_staff() then raise exception 'Staff role required'; end if;
  if p_score_grinta < 0 or p_score_adverse < 0 then raise exception 'Score invalide'; end if;

  delete from public.match_player_stats where match_id = p_match_id;
  delete from public.match_guest_stats where match_id = p_match_id;
  delete from public.match_motm where match_id = p_match_id;
  delete from public.match_participants where match_id = p_match_id;

  for item in select * from jsonb_array_elements(coalesce(p_player_stats, '[]'::jsonb)) loop
    insert into public.match_player_stats(
      match_id, profile_id, present, goals, assists, penalty_faults, clean_sheet
    ) values (
      p_match_id,
      (item->>'profile_id')::uuid,
      coalesce((item->>'present')::boolean, false),
      coalesce((item->>'goals')::integer, 0),
      coalesce((item->>'assists')::integer, 0),
      coalesce((item->>'penalty_faults')::integer, 0),
      coalesce((item->>'clean_sheet')::boolean, false)
    );

    if coalesce((item->>'present')::boolean, false) then
      insert into public.match_participants(match_id, profile_id)
      values (p_match_id, (item->>'profile_id')::uuid);
    end if;
  end loop;

  for item in select * from jsonb_array_elements(coalesce(p_guest_stats, '[]'::jsonb)) loop
    insert into public.match_guest_stats(match_id, display_name, goals, assists, penalty_faults)
    values (
      p_match_id,
      btrim(item->>'display_name'),
      coalesce((item->>'goals')::integer, 0),
      coalesce((item->>'assists')::integer, 0),
      coalesce((item->>'penalty_faults')::integer, 0)
    );
  end loop;

  if p_motm_profile_id is not null then
    insert into public.match_motm(match_id, profile_id, created_by)
    values (p_match_id, p_motm_profile_id, auth.uid());
  end if;

  update public.matches
  set score_as_grinta = p_score_grinta,
      score_adverse = p_score_adverse,
      status = 'termine',
      updated_at = now()
  where id = p_match_id;

  return found;
end;
$$;

revoke all on function public.finalize_match_postgame(uuid,integer,integer,uuid,jsonb,jsonb)
  from public, anon;
grant execute on function public.finalize_match_postgame(uuid,integer,integer,uuid,jsonb,jsonb)
  to authenticated;

create or replace view public.v_player_season_stats as
with base as (
  select m.season_id, s.profile_id,
         count(*) filter (where s.present)::int as matches_played,
         sum(s.goals)::int as goals,
         sum(s.assists)::int as assists,
         count(*) filter (where s.clean_sheet)::int as clean_sheets,
         sum(s.penalty_faults)::int as penalty_faults
  from public.match_player_stats s
  join public.matches m on m.id = s.match_id
  where m.status in ('termine','archive')
  group by m.season_id, s.profile_id
), motm as (
  select m.season_id, mm.profile_id, count(*)::int as motm
  from public.match_motm mm
  join public.matches m on m.id = mm.match_id
  group by m.season_id, mm.profile_id
)
select sp.season_id, sp.profile_id,
       coalesce(b.matches_played,0) as matches_played,
       coalesce(b.goals,0) as goals,
       coalesce(b.assists,0) as assists,
       coalesce(mt.motm,0) as motm,
       coalesce(b.clean_sheets,0) as clean_sheets,
       0::int as minutes_played,
       0::int as starts,
       0::int as substitute_appearances,
       coalesce(b.penalty_faults,0) as penalty_faults
from public.season_players sp
left join base b using (season_id, profile_id)
left join motm mt using (season_id, profile_id);

create or replace view public.v_player_career_stats as
select profile_id,
       sum(matches_played)::int as matches_played,
       sum(goals)::int as goals,
       sum(assists)::int as assists,
       sum(motm)::int as motm,
       sum(clean_sheets)::int as clean_sheets,
       sum(minutes_played)::int as minutes_played,
       sum(starts)::int as starts,
       sum(substitute_appearances)::int as substitute_appearances,
       sum(penalty_faults)::int as penalty_faults
from public.v_player_season_stats
group by profile_id;

create or replace view public.v_season_prediction_points as
select sp.id, sp.season_id, sp.predictor_profile_id, sp.player_profile_id, sp.category,
round(greatest(0::numeric,
  (1::numeric - (
    abs((case sp.category
      when 'buts' then stats.goals
      when 'passes' then stats.assists
      when 'hommes_du_match' then stats.motm
      when 'clean_sheets' then stats.clean_sheets
      when 'penalty_faults' then stats.penalty_faults
      else 0 end)::numeric - ((sp.predicted_value_20 * stats.matches_played)::numeric / 20.0))
    / greatest(((sp.predicted_value_20 * stats.matches_played)::numeric / 20.0), 1::numeric)
  )) * 20::numeric
))::integer as points
from public.season_predictions sp
join public.v_player_season_stats stats
  on stats.season_id = sp.season_id and stats.profile_id = sp.player_profile_id
join public.seasons s on s.id = sp.season_id
where sp.is_filled and stats.matches_played > 0
  and not (s.status = 'archived' and stats.matches_played < 3);
