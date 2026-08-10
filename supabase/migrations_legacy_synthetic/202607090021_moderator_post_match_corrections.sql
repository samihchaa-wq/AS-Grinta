create table if not exists public.match_correction_audit(
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  actor_profile_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check(
    action in('goal_added','goal_updated','goal_deleted','motm_updated')
  ),
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_match_correction_audit_match
on public.match_correction_audit(match_id,created_at desc);
alter table public.match_correction_audit enable row level security;
revoke insert,update,delete on public.match_correction_audit from authenticated;

drop policy if exists match_correction_audit_authenticated_read
on public.match_correction_audit;
create policy match_correction_audit_authenticated_read
on public.match_correction_audit
for select to authenticated using(true);

create or replace function public.refresh_match_score_from_goals(
  p_match_id uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  update public.matches
  set score_as_grinta=(
        select count(*)::integer
        from public.goals
        where match_id=p_match_id and team='as_grinta'
      ),
      score_adverse=(
        select count(*)::integer
        from public.goals
        where match_id=p_match_id and team='adverse'
      ),
      updated_at=now()
  where id=p_match_id
    and status in('termine','archive');
end;
$$;

revoke execute on function public.refresh_match_score_from_goals(uuid)
from public,anon,authenticated;

create or replace function public.moderator_add_match_goal(
  p_match_id uuid,
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
set search_path=public
as $$
declare
  new_id uuid;
  new_row jsonb;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required';
  end if;
  if not exists(
    select 1 from public.matches
    where id=p_match_id and status in('termine','archive')
  ) then
    raise exception 'Only finished matches can be corrected';
  end if;

  insert into public.goals(
    match_id,team,minute,goal_type,scorer_profile_id,
    assist_type,assist_profile_id
  ) values(
    p_match_id,p_team,p_minute,p_goal_type,p_scorer_profile_id,
    p_assist_type,p_assist_profile_id
  )
  returning id,to_jsonb(goals.*) into new_id,new_row;

  perform public.refresh_match_score_from_goals(p_match_id);
  insert into public.match_correction_audit(
    match_id,actor_profile_id,action,entity_id,after_data
  ) values(
    p_match_id,auth.uid(),'goal_added',new_id,new_row
  );
  return new_id;
end;
$$;

create or replace function public.moderator_update_match_goal(
  p_goal_id uuid,
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
set search_path=public
as $$
declare
  target_match uuid;
  old_row jsonb;
  new_row jsonb;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required';
  end if;

  select match_id,to_jsonb(g.*)
  into target_match,old_row
  from public.goals g
  where id=p_goal_id;

  if target_match is null or not exists(
    select 1 from public.matches
    where id=target_match and status in('termine','archive')
  ) then
    return false;
  end if;

  update public.goals
  set team=p_team,
      minute=p_minute,
      goal_type=p_goal_type,
      scorer_profile_id=p_scorer_profile_id,
      assist_type=p_assist_type,
      assist_profile_id=p_assist_profile_id
  where id=p_goal_id
  returning to_jsonb(goals.*) into new_row;

  perform public.refresh_match_score_from_goals(target_match);
  insert into public.match_correction_audit(
    match_id,actor_profile_id,action,entity_id,before_data,after_data
  ) values(
    target_match,auth.uid(),'goal_updated',p_goal_id,old_row,new_row
  );
  return true;
end;
$$;

create or replace function public.moderator_delete_match_goal(
  p_goal_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  target_match uuid;
  old_row jsonb;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required';
  end if;

  select match_id,to_jsonb(g.*)
  into target_match,old_row
  from public.goals g
  where id=p_goal_id;

  if target_match is null or not exists(
    select 1 from public.matches
    where id=target_match and status in('termine','archive')
  ) then
    return false;
  end if;

  delete from public.goals where id=p_goal_id;
  perform public.refresh_match_score_from_goals(target_match);
  insert into public.match_correction_audit(
    match_id,actor_profile_id,action,entity_id,before_data
  ) values(
    target_match,auth.uid(),'goal_deleted',p_goal_id,old_row
  );
  return true;
end;
$$;

create or replace function public.moderator_set_match_motm(
  p_match_id uuid,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  old_row jsonb;
  new_id uuid;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required';
  end if;
  if not exists(
    select 1 from public.matches
    where id=p_match_id and status in('termine','archive')
  ) then
    return false;
  end if;
  if not exists(
    select 1 from public.match_participants
    where match_id=p_match_id and profile_id=p_profile_id
  ) then
    raise exception 'MOTM must be a match participant';
  end if;

  select to_jsonb(mm.*)
  into old_row
  from public.match_motm mm
  where match_id=p_match_id
  limit 1;

  delete from public.match_motm where match_id=p_match_id;
  insert into public.match_motm(match_id,profile_id,created_by)
  values(p_match_id,p_profile_id,auth.uid())
  returning id into new_id;

  insert into public.match_correction_audit(
    match_id,actor_profile_id,action,entity_id,before_data,after_data
  ) values(
    p_match_id,
    auth.uid(),
    'motm_updated',
    new_id,
    old_row,
    jsonb_build_object('profile_id',p_profile_id)
  );
  return true;
end;
$$;

revoke execute on function public.moderator_add_match_goal(
  uuid,text,integer,text,uuid,text,uuid
) from public,anon;
grant execute on function public.moderator_add_match_goal(
  uuid,text,integer,text,uuid,text,uuid
) to authenticated;

revoke execute on function public.moderator_update_match_goal(
  uuid,text,integer,text,uuid,text,uuid
) from public,anon;
grant execute on function public.moderator_update_match_goal(
  uuid,text,integer,text,uuid,text,uuid
) to authenticated;

revoke execute on function public.moderator_delete_match_goal(uuid)
from public,anon;
grant execute on function public.moderator_delete_match_goal(uuid)
to authenticated;

revoke execute on function public.moderator_set_match_motm(uuid,uuid)
from public,anon;
grant execute on function public.moderator_set_match_motm(uuid,uuid)
to authenticated;
