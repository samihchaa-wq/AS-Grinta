alter table public.goals drop constraint if exists goals_players_consistency;
alter table public.goals add constraint goals_players_consistency check(
 (team='adverse' and scorer_profile_id is null and assist_profile_id is null and assist_type is null)
 or (team='as_grinta' and goal_type='csc_adverse' and scorer_profile_id is null and assist_profile_id is null and assist_type is null)
 or (team='as_grinta' and goal_type in('jeu','penalty','coup_franc') and scorer_profile_id is not null
     and ((assist_type='connu' and assist_profile_id is not null) or (assist_type in('sans_passe','inconnu') and assist_profile_id is null))
     and assist_profile_id is distinct from scorer_profile_id)
);

alter table public.matches drop constraint if exists matches_created_by_required;
alter table public.matches add constraint matches_created_by_required check(created_by is not null) not valid;
alter table public.match_motm alter column created_by set not null;
alter table public.match_motm drop constraint if exists match_motm_created_by_fkey;
alter table public.match_motm add constraint match_motm_created_by_fkey foreign key(created_by) references public.profiles(id) on delete restrict;

create or replace function public.guard_single_match_date()
returns trigger language plpgsql set search_path=public as $$
begin
 if exists(select 1 from public.matches m where m.match_date=new.match_date and m.id<>new.id) then
  raise exception 'A match already exists on this date';
 end if;
 return new;
end $$;
drop trigger if exists trg_guard_single_match_date on public.matches;
create trigger trg_guard_single_match_date before insert on public.matches for each row execute function public.guard_single_match_date();

create or replace function public.compute_match_odds(p_match_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_opponent uuid; lf numeric; la numeric; gap numeric; pd numeric; share numeric; pw numeric; pl numeric;
begin
 select opponent_id into v_opponent from public.matches where id=p_match_id;
 if v_opponent is null then raise exception 'Match not found'; end if;
 with rs as(select id,row_number() over(order by name desc)-1 age from public.seasons),h as(
  select m.score_as_grinta::numeric gf,m.score_adverse::numeric ga,
  (case rs.age when 0 then .40 when 1 then .25 when 2 then .18 when 3 then .10 else .07 end)
  *(case when m.opponent_id=v_opponent then 1.5 else 1 end) w
  from public.matches m join rs on rs.id=m.season_id
  where m.status in('termine','archive') and m.score_as_grinta is not null and m.score_adverse is not null)
 select coalesce(sum(gf*w)/nullif(sum(w),0),1.5),coalesce(sum(ga*w)/nullif(sum(w),0),1.5) into lf,la from h;
 gap:=(lf-la)/(lf+la+.001);
 pd:=case when abs(gap)<.15 then .30 when abs(gap)<.35 then .25 when abs(gap)<.55 then .21 else .17 end;
 pd:=greatest(pd,.155); share:=.5+least(.32,abs(gap)/2);
 pw:=case when gap>0 then (1-pd)*share else (1-pd)*(1-share) end;
 pw:=least(pw,.82); pl:=1-pd-pw;
 insert into public.match_odds(match_id,odds_victoire_as_grinta,odds_nul,odds_victoire_adverse,computed_at)
 values(p_match_id,round((1/(pw*1.05))::numeric,2),round((1/(pd*1.05))::numeric,2),round((1/(pl*1.05))::numeric,2),now())
 on conflict(match_id) do nothing;
end $$;
create or replace function public.create_match_odds_after_insert() returns trigger language plpgsql security definer set search_path=public as $$ begin perform public.compute_match_odds(new.id); return new; end $$;
drop trigger if exists trg_create_match_odds on public.matches;
create trigger trg_create_match_odds after insert on public.matches for each row execute function public.create_match_odds_after_insert();

create or replace function public.move_live_player(p_match_id uuid,p_controller_session_id text,p_profile_id uuid,p_slot_code text)
returns boolean language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 select id into sid from public.live_sessions where match_id=p_match_id and controller_profile_id=auth.uid() and controller_session_id=p_controller_session_id;
 if sid is null then return false; end if;
 if not exists(select 1 from public.match_participants where match_id=p_match_id and profile_id=p_profile_id) then raise exception 'Player is not a match participant'; end if;
 delete from public.live_positions where live_session_id=sid and (profile_id=p_profile_id or (p_slot_code is not null and slot_code=p_slot_code));
 if p_slot_code is not null and p_slot_code<>'bench' then insert into public.live_positions(live_session_id,profile_id,slot_code) values(sid,p_profile_id,p_slot_code); end if;
 return true;
end $$;

create or replace function public.record_substitution(p_match_id uuid,p_controller_session_id text,p_minute int,p_in_profile_id uuid,p_out_profile_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare sid uuid; outslot text;
begin
 if p_minute<0 or p_minute>100 or p_in_profile_id=p_out_profile_id then raise exception 'Invalid substitution'; end if;
 select id into sid from public.live_sessions where match_id=p_match_id and controller_profile_id=auth.uid() and controller_session_id=p_controller_session_id;
 if sid is null then return false; end if;
 select slot_code into outslot from public.live_positions where live_session_id=sid and profile_id=p_out_profile_id and slot_code is not null;
 if outslot is null then raise exception 'Outgoing player is not on pitch'; end if;
 if exists(select 1 from public.live_positions where live_session_id=sid and profile_id=p_in_profile_id and slot_code is not null) then raise exception 'Incoming player is not on bench'; end if;
 insert into public.substitutions(live_session_id,profile_id,action,minute) values(sid,p_out_profile_id,'out',p_minute),(sid,p_in_profile_id,'in',p_minute);
 delete from public.live_positions where live_session_id=sid and profile_id in(p_in_profile_id,p_out_profile_id);
 insert into public.live_positions(live_session_id,profile_id,slot_code) values(sid,p_in_profile_id,outslot);
 return true;
end $$;

create or replace function public.finalize_match(p_match_id uuid,p_score_as_grinta int,p_score_adverse int,p_motm_profile_id uuid default null)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin role required'; end if;
 if p_score_as_grinta<0 or p_score_as_grinta>99 or p_score_adverse<0 or p_score_adverse>99 then raise exception 'Invalid score'; end if;
 update public.matches set score_as_grinta=p_score_as_grinta,score_adverse=p_score_adverse,status='termine',updated_at=now() where id=p_match_id and status<>'archive';
 if not found then return false; end if;
 update public.live_sessions set status='finished',controller_profile_id=null,controller_session_id=null,controller_disconnected_at=null,clock_started_at=null,updated_at=now() where match_id=p_match_id;
 delete from public.match_motm where match_id=p_match_id;
 if p_motm_profile_id is not null then
  if not exists(select 1 from public.match_participants where match_id=p_match_id and profile_id=p_motm_profile_id) then raise exception 'MOTM must be a match participant'; end if;
  insert into public.match_motm(match_id,profile_id,created_by) values(p_match_id,p_motm_profile_id,auth.uid());
 end if;
 return true;
end $$;

grant execute on function public.compute_match_odds(uuid) to authenticated;
grant execute on function public.move_live_player(uuid,text,uuid,text) to authenticated;
grant execute on function public.record_substitution(uuid,text,int,uuid,uuid) to authenticated;
grant execute on function public.finalize_match(uuid,int,int,uuid) to authenticated;;
