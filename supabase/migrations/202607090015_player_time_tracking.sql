create table if not exists public.match_player_intervals(
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  entered_minute integer not null check(entered_minute between 0 and 100),
  exited_minute integer check(exited_minute between 0 and 100),
  started boolean not null default false,
  created_at timestamptz not null default now(),
  unique(match_id,profile_id,entered_minute),
  check(exited_minute is null or exited_minute>=entered_minute)
);

create index if not exists idx_match_player_intervals_match
on public.match_player_intervals(match_id);
create index if not exists idx_match_player_intervals_profile
on public.match_player_intervals(profile_id);
alter table public.match_player_intervals enable row level security;

drop policy if exists match_player_intervals_read_authenticated
on public.match_player_intervals;
create policy match_player_intervals_read_authenticated
on public.match_player_intervals
for select to authenticated using(true);
revoke insert,update,delete on public.match_player_intervals from authenticated;

create or replace function public.update_live_status(
  p_match_id uuid,
  p_controller_session_id text,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  affected integer;
  live_id uuid;
begin
  if p_status not in('not_started','running','paused','halftime','finished') then
    raise exception 'Invalid live status';
  end if;
  if not public.is_exact_live_controller(p_match_id,p_controller_session_id) then
    return false;
  end if;

  select id into live_id
  from public.live_sessions
  where match_id=p_match_id;

  if p_status='running' and not exists(
    select 1 from public.match_player_intervals where match_id=p_match_id
  ) then
    insert into public.match_player_intervals(
      match_id,profile_id,entered_minute,started
    )
    select p_match_id,lp.profile_id,0,true
    from public.live_positions lp
    where lp.live_session_id=live_id
      and lp.slot_code is not null
    on conflict do nothing;
  end if;

  update public.live_sessions
  set elapsed_seconds=case
        when status='running' and clock_started_at is not null
          then elapsed_seconds+
            greatest(0,floor(extract(epoch from(now()-clock_started_at)))::integer)
        else elapsed_seconds
      end,
      status=p_status,
      clock_started_at=case when p_status='running' then now() else null end,
      updated_at=now()
  where match_id=p_match_id
    and controller_profile_id=auth.uid()
    and controller_session_id=p_controller_session_id;

  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

create or replace function public.record_substitution(
  p_match_id uuid,
  p_controller_session_id text,
  p_minute integer,
  p_in_profile_id uuid,
  p_out_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  sid uuid;
  outslot text;
begin
  if p_minute<0 or p_minute>100 or p_in_profile_id=p_out_profile_id then
    raise exception 'Invalid substitution';
  end if;
  if not public.is_exact_live_controller(p_match_id,p_controller_session_id) then
    return false;
  end if;

  select id into sid
  from public.live_sessions
  where match_id=p_match_id;

  select slot_code into outslot
  from public.live_positions
  where live_session_id=sid
    and profile_id=p_out_profile_id
    and slot_code is not null;

  if outslot is null then
    raise exception 'Outgoing player is not on pitch';
  end if;
  if exists(
    select 1 from public.live_positions
    where live_session_id=sid
      and profile_id=p_in_profile_id
      and slot_code is not null
  ) then
    raise exception 'Incoming player is not on bench';
  end if;

  insert into public.substitutions(live_session_id,profile_id,action,minute)
  values
    (sid,p_out_profile_id,'out',p_minute),
    (sid,p_in_profile_id,'in',p_minute);

  update public.match_player_intervals
  set exited_minute=p_minute
  where match_id=p_match_id
    and profile_id=p_out_profile_id
    and exited_minute is null;

  insert into public.match_player_intervals(
    match_id,profile_id,entered_minute,started
  ) values(p_match_id,p_in_profile_id,p_minute,false)
  on conflict(match_id,profile_id,entered_minute) do nothing;

  delete from public.live_positions
  where live_session_id=sid
    and profile_id in(p_in_profile_id,p_out_profile_id);

  insert into public.live_positions(live_session_id,profile_id,slot_code)
  values(sid,p_in_profile_id,outslot);

  return true;
end;
$$;

create or replace function public.finalize_match(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_motm_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  final_minute integer;
begin
  if not public.is_admin() then raise exception 'Admin role required'; end if;
  if p_motm_profile_id is null then raise exception 'MOTM is required'; end if;
  if p_score_as_grinta<0 or p_score_as_grinta>99
     or p_score_adverse<0 or p_score_adverse>99 then
    raise exception 'Invalid score';
  end if;
  if not exists(
    select 1 from public.match_participants
    where match_id=p_match_id and profile_id=p_motm_profile_id
  ) then
    raise exception 'MOTM must be a match participant';
  end if;
  if p_score_as_grinta<>(
       select count(*) from public.goals
       where match_id=p_match_id and team='as_grinta'
     )
     or p_score_adverse<>(
       select count(*) from public.goals
       where match_id=p_match_id and team='adverse'
     ) then
    raise exception 'Score does not match recorded goals';
  end if;

  select greatest(
    planned_duration_minutes,
    coalesce((
      select max(minute) from public.goals where match_id=p_match_id
    ),0),
    coalesce((
      select max(s.minute)
      from public.substitutions s
      join public.live_sessions ls on ls.id=s.live_session_id
      where ls.match_id=p_match_id
    ),0)
  ) into final_minute
  from public.matches
  where id=p_match_id;

  update public.match_player_intervals
  set exited_minute=least(100,final_minute)
  where match_id=p_match_id
    and exited_minute is null;

  update public.matches
  set score_as_grinta=p_score_as_grinta,
      score_adverse=p_score_adverse,
      status='termine',
      updated_at=now()
  where id=p_match_id
    and status<>'archive';
  if not found then return false; end if;

  update public.live_sessions
  set status='finished',
      controller_profile_id=null,
      controller_session_id=null,
      controller_disconnected_at=null,
      clock_started_at=null,
      updated_at=now()
  where match_id=p_match_id;

  delete from public.match_motm where match_id=p_match_id;
  insert into public.match_motm(match_id,profile_id,created_by)
  values(p_match_id,p_motm_profile_id,auth.uid());
  return true;
end;
$$;

create or replace view public.v_player_season_stats
with (security_invoker=true)
as
with appearances as(
  select m.season_id,mp.profile_id,
         count(distinct mp.match_id)::integer matches_played
  from public.match_participants mp
  join public.matches m on m.id=mp.match_id
  where m.status in('termine','archive')
  group by m.season_id,mp.profile_id
), goal_stats as(
  select m.season_id,g.scorer_profile_id profile_id,
         count(*) filter(
           where g.team='as_grinta' and g.scorer_profile_id is not null
         )::integer goals
  from public.goals g
  join public.matches m on m.id=g.match_id
  where m.status in('termine','archive')
  group by m.season_id,g.scorer_profile_id
), assist_stats as(
  select m.season_id,g.assist_profile_id profile_id,
         count(*) filter(
           where g.team='as_grinta' and g.assist_profile_id is not null
         )::integer assists
  from public.goals g
  join public.matches m on m.id=g.match_id
  where m.status in('termine','archive')
  group by m.season_id,g.assist_profile_id
), motm_stats as(
  select m.season_id,mm.profile_id,count(*)::integer motm
  from public.match_motm mm
  join public.matches m on m.id=mm.match_id
  group by m.season_id,mm.profile_id
), clean_sheet_stats as(
  select m.season_id,mp.profile_id,
         count(*) filter(where m.score_adverse=0)::integer clean_sheets
  from public.match_participants mp
  join public.matches m on m.id=mp.match_id
  join public.season_players sp
    on sp.season_id=m.season_id
   and sp.profile_id=mp.profile_id
   and sp.is_goalkeeper_snapshot
  where m.status in('termine','archive')
  group by m.season_id,mp.profile_id
), time_stats as(
  select m.season_id,i.profile_id,
         sum(greatest(
           0,
           coalesce(i.exited_minute,m.planned_duration_minutes)-i.entered_minute
         ))::integer minutes_played,
         count(*) filter(where i.started)::integer starts,
         count(*) filter(where not i.started)::integer substitute_appearances
  from public.match_player_intervals i
  join public.matches m on m.id=i.match_id
  where m.status in('termine','archive')
  group by m.season_id,i.profile_id
)
select
  sp.season_id,
  sp.profile_id,
  coalesce(a.matches_played,0) matches_played,
  coalesce(g.goals,0) goals,
  coalesce(ast.assists,0) assists,
  coalesce(mm.motm,0) motm,
  coalesce(cs.clean_sheets,0) clean_sheets,
  coalesce(ts.minutes_played,0) minutes_played,
  coalesce(ts.starts,0) starts,
  coalesce(ts.substitute_appearances,0) substitute_appearances
from public.season_players sp
left join appearances a using(season_id,profile_id)
left join goal_stats g using(season_id,profile_id)
left join assist_stats ast using(season_id,profile_id)
left join motm_stats mm using(season_id,profile_id)
left join clean_sheet_stats cs using(season_id,profile_id)
left join time_stats ts using(season_id,profile_id);

create or replace view public.v_player_career_stats
with (security_invoker=true)
as
select
  profile_id,
  sum(matches_played)::integer matches_played,
  sum(goals)::integer goals,
  sum(assists)::integer assists,
  sum(motm)::integer motm,
  sum(clean_sheets)::integer clean_sheets,
  sum(minutes_played)::integer minutes_played,
  sum(starts)::integer starts,
  sum(substitute_appearances)::integer substitute_appearances
from public.v_player_season_stats
group by profile_id;

grant select on public.match_player_intervals to authenticated;
grant select on public.v_player_season_stats to authenticated;
grant select on public.v_player_career_stats to authenticated;
