create or replace function public.guard_sensitive_profile_fields()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if auth.uid()=old.id and not public.is_moderator() then
  if new.role is distinct from old.role or new.status is distinct from old.status or new.is_goalkeeper is distinct from old.is_goalkeeper then
   raise exception 'Sensitive profile fields require Moderator role';
  end if;
 end if;
 return new;
end $$;
drop trigger if exists trg_guard_sensitive_profile_fields on public.profiles;
create trigger trg_guard_sensitive_profile_fields before update on public.profiles for each row execute function public.guard_sensitive_profile_fields();

create or replace function public.claim_live_control(p_match_id uuid,p_controller_session_id text)
returns boolean language plpgsql security definer set search_path=public as $$
declare n int;
begin
 if not public.is_admin() then raise exception 'Admin role required'; end if;
 update public.live_sessions set controller_profile_id=auth.uid(),controller_session_id=p_controller_session_id,controller_disconnected_at=null,updated_at=now()
 where match_id=p_match_id and controller_profile_id is null and controller_session_id is null;
 get diagnostics n=row_count; return n=1;
end $$;

create or replace function public.update_live_status(p_match_id uuid,p_controller_session_id text,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
declare n int;
begin
 if p_status not in('not_started','running','paused','halftime','finished') then raise exception 'Invalid live status'; end if;
 update public.live_sessions set
 elapsed_seconds=case when status='running' and clock_started_at is not null then elapsed_seconds+greatest(0,floor(extract(epoch from(now()-clock_started_at)))::int) else elapsed_seconds end,
 status=p_status,clock_started_at=case when p_status='running' then now() else null end,updated_at=now()
 where match_id=p_match_id and controller_profile_id=auth.uid() and controller_session_id=p_controller_session_id;
 get diagnostics n=row_count; return n=1;
end $$;

create or replace function public.release_live_control(p_match_id uuid,p_controller_session_id text)
returns boolean language plpgsql security definer set search_path=public as $$
declare n int;
begin
 update public.live_sessions set controller_profile_id=null,controller_session_id=null,controller_disconnected_at=null,updated_at=now()
 where match_id=p_match_id and controller_profile_id=auth.uid() and controller_session_id=p_controller_session_id;
 get diagnostics n=row_count; return n=1;
end $$;

create or replace function public.mark_live_disconnected(p_match_id uuid,p_controller_session_id text)
returns boolean language plpgsql security definer set search_path=public as $$
declare n int;
begin
 update public.live_sessions set controller_disconnected_at=now(),updated_at=now()
 where match_id=p_match_id and controller_profile_id=auth.uid() and controller_session_id=p_controller_session_id;
 get diagnostics n=row_count; return n=1;
end $$;

create or replace function public.force_resume_live(p_match_id uuid,p_controller_session_id text)
returns boolean language plpgsql security definer set search_path=public as $$
declare n int;
begin
 if not public.is_moderator() then raise exception 'Moderator role required'; end if;
 update public.live_sessions set controller_profile_id=auth.uid(),controller_session_id=p_controller_session_id,controller_disconnected_at=null,updated_at=now()
 where match_id=p_match_id and controller_disconnected_at is not null and controller_disconnected_at<=now()-interval '60 seconds';
 get diagnostics n=row_count; return n=1;
end $$;

create or replace function public.is_current_live_controller(p_live_session_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.live_sessions where id=p_live_session_id and controller_profile_id=auth.uid() and controller_session_id is not null and public.is_admin())
$$;
create or replace function public.is_current_match_controller(p_match_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.live_sessions where match_id=p_match_id and controller_profile_id=auth.uid() and controller_session_id is not null and public.is_admin())
$$;

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

drop policy if exists update_own_profile on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy profiles_moderator_update on public.profiles for update to authenticated using(public.is_moderator()) with check(public.is_moderator());

create policy seasons_moderator_insert on public.seasons for insert to authenticated with check(public.is_moderator());
create policy seasons_moderator_update on public.seasons for update to authenticated using(public.is_moderator()) with check(public.is_moderator());
create policy seasons_moderator_delete on public.seasons for delete to authenticated using(public.is_moderator());
create policy season_players_moderator_insert on public.season_players for insert to authenticated with check(public.is_moderator());
create policy season_players_moderator_update on public.season_players for update to authenticated using(public.is_moderator()) with check(public.is_moderator());
create policy season_players_moderator_delete on public.season_players for delete to authenticated using(public.is_moderator());

create policy opponents_admin_insert on public.opponents for insert to authenticated with check(public.is_admin() or public.is_moderator());
create policy opponents_moderator_update on public.opponents for update to authenticated using(public.is_moderator()) with check(public.is_moderator());
create policy opponents_moderator_delete on public.opponents for delete to authenticated using(public.is_moderator());

create policy matches_admin_insert on public.matches for insert to authenticated with check(public.is_admin() and created_by=auth.uid());
create policy matches_admin_update on public.matches for update to authenticated using(public.is_admin() and status<>'archive') with check(public.is_admin());
create policy matches_moderator_update on public.matches for update to authenticated using(public.is_moderator()) with check(public.is_moderator());
create policy matches_moderator_delete on public.matches for delete to authenticated using(public.is_moderator());

create policy match_participants_admin_insert on public.match_participants for insert to authenticated with check(public.is_admin() and exists(select 1 from public.matches m where m.id=match_id and m.status<>'archive'));
create policy match_participants_admin_delete on public.match_participants for delete to authenticated using(public.is_admin() and exists(select 1 from public.matches m where m.id=match_id and m.status<>'archive'));

create policy live_sessions_admin_insert on public.live_sessions for insert to authenticated with check(public.is_admin());
create policy live_sessions_controller_update on public.live_sessions for update to authenticated using((public.is_admin() and controller_profile_id=auth.uid()) or public.is_moderator()) with check((public.is_admin() and controller_profile_id=auth.uid()) or public.is_moderator());
create policy live_positions_controller_insert on public.live_positions for insert to authenticated with check(public.is_current_live_controller(live_session_id));
create policy live_positions_controller_update on public.live_positions for update to authenticated using(public.is_current_live_controller(live_session_id)) with check(public.is_current_live_controller(live_session_id));
create policy live_positions_controller_delete on public.live_positions for delete to authenticated using(public.is_current_live_controller(live_session_id));
create policy goals_controller_insert on public.goals for insert to authenticated with check(public.is_current_match_controller(match_id));
create policy goals_controller_update on public.goals for update to authenticated using(public.is_current_match_controller(match_id)) with check(public.is_current_match_controller(match_id));
create policy goals_controller_delete on public.goals for delete to authenticated using(public.is_current_match_controller(match_id));
create policy substitutions_controller_insert on public.substitutions for insert to authenticated with check(public.is_current_live_controller(live_session_id));
create policy substitutions_controller_delete on public.substitutions for delete to authenticated using(public.is_current_live_controller(live_session_id));
create policy match_motm_admin_insert on public.match_motm for insert to authenticated with check(public.is_admin() and created_by=auth.uid());
create policy match_motm_admin_delete on public.match_motm for delete to authenticated using(public.is_admin() or public.is_moderator());

drop policy if exists update_own_match_prediction on public.match_predictions;
create policy match_predictions_owner_insert on public.match_predictions for insert to authenticated with check(profile_id=auth.uid());
create policy match_predictions_owner_update_window on public.match_predictions for update to authenticated using(profile_id=auth.uid()) with check(profile_id=auth.uid() and exists(select 1 from public.matches m where m.id=match_id and m.status='a_venir' and now()>=(m.match_date+m.match_time)-interval '6 days' and now()<(m.match_date+m.match_time)-interval '12 hours'));

drop policy if exists update_own_season_prediction on public.season_predictions;
create policy season_predictions_owner_insert on public.season_predictions for insert to authenticated with check(predictor_profile_id=auth.uid());
create policy season_predictions_owner_update on public.season_predictions for update to authenticated using(predictor_profile_id=auth.uid()) with check(predictor_profile_id=auth.uid());

revoke insert,update,delete on public.match_odds from authenticated;
revoke insert,update,delete on public.formations from authenticated;

grant execute on function public.claim_live_control(uuid,text) to authenticated;
grant execute on function public.update_live_status(uuid,text,text) to authenticated;
grant execute on function public.release_live_control(uuid,text) to authenticated;
grant execute on function public.mark_live_disconnected(uuid,text) to authenticated;
grant execute on function public.force_resume_live(uuid,text) to authenticated;;
