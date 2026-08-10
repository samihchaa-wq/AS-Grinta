revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;

grant execute on function public.current_profile_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_moderator() to authenticated;
grant execute on function public.is_current_live_controller(uuid) to authenticated;
grant execute on function public.is_current_match_controller(uuid) to authenticated;
grant execute on function public.claim_live_control(uuid,text) to authenticated;
grant execute on function public.release_live_control(uuid,text) to authenticated;
grant execute on function public.mark_live_disconnected(uuid,text) to authenticated;
grant execute on function public.force_resume_live(uuid,text) to authenticated;
grant execute on function public.update_live_status(uuid,text,text) to authenticated;
grant execute on function public.create_live_session_if_missing(uuid) to authenticated;
grant execute on function public.move_live_player(uuid,text,uuid,text) to authenticated;
grant execute on function public.record_substitution(uuid,text,integer,uuid,uuid) to authenticated;
grant execute on function public.finalize_match(uuid,integer,integer,uuid) to authenticated;
grant execute on function public.archive_match(uuid) to authenticated;

create or replace function public.is_exact_live_controller(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.live_sessions ls
    join public.profiles p on p.id = auth.uid()
    where ls.match_id = p_match_id
      and ls.controller_profile_id = auth.uid()
      and ls.controller_session_id = p_controller_session_id
      and p.role in ('admin','moderateur')
      and p.status = 'active'
  );
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
  if not public.is_exact_live_controller(p_match_id,p_controller_session_id) then
    return false;
  end if;
  update public.live_sessions
  set elapsed_seconds = case
        when status = 'running' and clock_started_at is not null
          then elapsed_seconds + greatest(0,floor(extract(epoch from(now()-clock_started_at)))::integer)
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

create or replace function public.set_live_formation(
  p_match_id uuid,
  p_controller_session_id text,
  p_formation text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_exact_live_controller(p_match_id,p_controller_session_id) then
    return false;
  end if;
  if not exists(select 1 from public.formations where code=p_formation) then
    raise exception 'Unknown formation';
  end if;
  update public.live_sessions
  set formation=p_formation, updated_at=now()
  where match_id=p_match_id
    and controller_profile_id=auth.uid()
    and controller_session_id=p_controller_session_id;
  return found;
end;
$$;

create or replace function public.add_live_goal(
  p_match_id uuid,
  p_controller_session_id text,
  p_team text,
  p_minute integer,
  p_goal_type text,
  p_scorer_profile_id uuid,
  p_assist_type text,
  p_assist_profile_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if not public.is_exact_live_controller(p_match_id,p_controller_session_id) then
    raise exception 'Live control required';
  end if;
  insert into public.goals(
    match_id,team,minute,goal_type,scorer_profile_id,assist_type,assist_profile_id
  ) values (
    p_match_id,p_team,p_minute,p_goal_type,p_scorer_profile_id,p_assist_type,p_assist_profile_id
  ) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.update_live_goal(
  p_goal_id uuid,
  p_controller_session_id text,
  p_team text,
  p_minute integer,
  p_goal_type text,
  p_scorer_profile_id uuid,
  p_assist_type text,
  p_assist_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_match uuid;
begin
  select match_id into target_match from public.goals where id=p_goal_id;
  if target_match is null or not public.is_exact_live_controller(target_match,p_controller_session_id) then
    return false;
  end if;
  update public.goals
  set team=p_team,minute=p_minute,goal_type=p_goal_type,
      scorer_profile_id=p_scorer_profile_id,assist_type=p_assist_type,
      assist_profile_id=p_assist_profile_id
  where id=p_goal_id;
  return found;
end;
$$;

create or replace function public.delete_live_goal(
  p_goal_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_match uuid;
begin
  select match_id into target_match from public.goals where id=p_goal_id;
  if target_match is null or not public.is_exact_live_controller(target_match,p_controller_session_id) then
    return false;
  end if;
  delete from public.goals where id=p_goal_id;
  return found;
end;
$$;

revoke insert,update,delete on public.goals from authenticated;
revoke insert,update,delete on public.live_positions from authenticated;
revoke insert,update,delete on public.substitutions from authenticated;
revoke update on public.live_sessions from authenticated;

grant execute on function public.is_exact_live_controller(uuid,text) to authenticated;
grant execute on function public.set_live_formation(uuid,text,text) to authenticated;
grant execute on function public.add_live_goal(uuid,text,text,integer,text,uuid,text,uuid) to authenticated;
grant execute on function public.update_live_goal(uuid,text,text,integer,text,uuid,text,uuid) to authenticated;
grant execute on function public.delete_live_goal(uuid,text) to authenticated;

revoke execute on function public.apply_substitution_to_positions() from authenticated;
revoke execute on function public.create_match_odds_after_insert() from authenticated;
revoke execute on function public.guard_live_session_update() from authenticated;
revoke execute on function public.guard_sensitive_profile_fields() from authenticated;
revoke execute on function public.seed_match_predictions() from authenticated;
revoke execute on function public.seed_predictions_for_active_profile() from authenticated;
revoke execute on function public.seed_season_predictions_for_player() from authenticated;
revoke execute on function public.compute_match_odds(uuid) from authenticated;
