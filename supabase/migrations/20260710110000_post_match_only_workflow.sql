begin;

alter table public.matches
  add column if not exists competition text not null default 'Championnat',
  add column if not exists result_validated_at timestamptz;

alter table public.match_guest_stats
  add column if not exists position text not null default 'Joueur',
  add column if not exists present boolean not null default true;

create unique index if not exists match_player_stats_match_profile_uidx
  on public.match_player_stats(match_id, profile_id);
create unique index if not exists match_predictions_match_profile_uidx
  on public.match_predictions(match_id, profile_id);
create unique index if not exists match_participants_match_profile_uidx
  on public.match_participants(match_id, profile_id);

drop function if exists public.accept_live_control(uuid,text) cascade;
drop function if exists public.add_live_goal(uuid,text,text,integer,text,uuid,text,uuid) cascade;
drop function if exists public.cancel_live_control_offer(uuid,text) cascade;
drop function if exists public.claim_live_control(uuid,text) cascade;
drop function if exists public.create_live_session_if_missing(uuid) cascade;
drop function if exists public.delete_live_goal(uuid,text) cascade;
drop function if exists public.finish_coach_match(uuid) cascade;
drop function if exists public.force_resume_live(uuid,text) cascade;
drop function if exists public.guard_live_session_update() cascade;
drop function if exists public.is_current_live_controller(uuid) cascade;
drop function if exists public.is_current_match_controller(uuid) cascade;
drop function if exists public.is_exact_live_controller(uuid,text) cascade;
drop function if exists public.live_session_token_hash(text) cascade;
drop function if exists public.mark_live_disconnected(uuid,text) cascade;
drop function if exists public.mark_live_reconnected(uuid,text) cascade;
drop function if exists public.move_live_player(uuid,text,uuid,text) cascade;
drop function if exists public.offer_live_control(uuid,text,uuid) cascade;
drop function if exists public.release_live_control(uuid,text) cascade;
drop function if exists public.set_live_formation(uuid,text,text) cascade;
drop function if exists public.start_coach_match(uuid) cascade;
drop function if exists public.update_live_goal(uuid,text,text,integer,text,uuid,text,uuid) cascade;
drop function if exists public.update_live_status(uuid,text,text) cascade;
drop function if exists public.assert_match_live_editable() cascade;

drop table if exists public.live_control_handoffs cascade;
drop table if exists public.coach_match_events cascade;
drop table if exists public.coach_match_sessions cascade;
drop table if exists public.substitutions cascade;
drop table if exists public.live_positions cascade;
drop table if exists public.live_sessions cascade;
drop table if exists public.formations cascade;
drop table if exists public.match_player_intervals cascade;

drop policy if exists goals_controller_delete on public.goals;
drop policy if exists goals_controller_insert on public.goals;
drop policy if exists goals_controller_update on public.goals;
create policy goals_staff_write on public.goals
  for all to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());

create or replace function public.match_prediction_participant_count(p_match_id uuid)
returns integer
language sql
stable
security definer
set search_path=public
as $$
  select count(*)::integer
  from public.match_predictions
  where match_id=p_match_id and is_filled;
$$;
grant execute on function public.match_prediction_participant_count(uuid) to authenticated;

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
set search_path=public
as $$
declare
  item jsonb;
  computed_score_grinta integer := 0;
begin
  if not public.is_match_staff() then raise exception 'Staff role required'; end if;
  if p_score_adverse < 0 then raise exception 'Score adverse invalide'; end if;

  select coalesce(sum(coalesce((x->>'goals')::integer,0)),0)::integer
    into computed_score_grinta
  from jsonb_array_elements(coalesce(p_player_stats,'[]'::jsonb)) x;
  select computed_score_grinta + coalesce(sum(coalesce((x->>'goals')::integer,0)),0)::integer
    into computed_score_grinta
  from jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb)) x;

  delete from public.match_player_stats where match_id=p_match_id;
  delete from public.match_guest_stats where match_id=p_match_id;
  delete from public.match_motm where match_id=p_match_id;
  delete from public.match_participants where match_id=p_match_id;

  for item in select * from jsonb_array_elements(coalesce(p_player_stats,'[]'::jsonb)) loop
    insert into public.match_player_stats(match_id,profile_id,present,goals,assists,penalty_faults,clean_sheet)
    values(
      p_match_id,
      (item->>'profile_id')::uuid,
      coalesce((item->>'present')::boolean,false),
      greatest(coalesce((item->>'goals')::integer,0),0),
      greatest(coalesce((item->>'assists')::integer,0),0),
      greatest(coalesce((item->>'penalty_faults')::integer,0),0),
      coalesce((item->>'clean_sheet')::boolean,false)
    );
    if coalesce((item->>'present')::boolean,false) then
      insert into public.match_participants(match_id,profile_id)
      values(p_match_id,(item->>'profile_id')::uuid)
      on conflict(match_id,profile_id) do nothing;
    end if;
  end loop;

  for item in select * from jsonb_array_elements(coalesce(p_guest_stats,'[]'::jsonb)) loop
    if btrim(coalesce(item->>'display_name',''))='' then raise exception 'Nom invité requis'; end if;
    insert into public.match_guest_stats(match_id,display_name,position,present,goals,assists,penalty_faults)
    values(
      p_match_id,
      btrim(item->>'display_name'),
      coalesce(nullif(btrim(item->>'position'),''),'Joueur'),
      coalesce((item->>'present')::boolean,true),
      greatest(coalesce((item->>'goals')::integer,0),0),
      greatest(coalesce((item->>'assists')::integer,0),0),
      greatest(coalesce((item->>'penalty_faults')::integer,0),0)
    );
  end loop;

  if p_motm_profile_id is not null then
    insert into public.match_motm(match_id,profile_id,created_by)
    values(p_match_id,p_motm_profile_id,auth.uid());
  end if;

  update public.matches
  set score_as_grinta=computed_score_grinta,
      score_adverse=p_score_adverse,
      status='termine',
      result_validated_at=now(),
      updated_at=now()
  where id=p_match_id;

  return found;
end;
$$;

drop trigger if exists guard_match_prediction_window on public.match_predictions;
create trigger guard_match_prediction_window
before insert or update on public.match_predictions
for each row execute function public.guard_match_prediction_window();

commit;
