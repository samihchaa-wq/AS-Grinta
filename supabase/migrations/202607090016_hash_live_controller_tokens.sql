create or replace function public.live_session_token_hash(p_token text)
returns text
language sql
immutable
strict
set search_path=public,extensions
as $$
  select encode(
    extensions.digest(convert_to(p_token,'UTF8'),'sha256'),
    'hex'
  );
$$;

revoke execute on function public.live_session_token_hash(text) from public;
revoke execute on function public.live_session_token_hash(text) from anon;
revoke execute on function public.live_session_token_hash(text) from authenticated;

create or replace function public.claim_live_control(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  affected integer;
begin
  if not public.is_admin() then
    raise exception 'Admin role required';
  end if;
  if coalesce(length(p_controller_session_id),0)<32 then
    raise exception 'Invalid controller token';
  end if;

  update public.live_sessions
  set controller_profile_id=auth.uid(),
      controller_session_id=public.live_session_token_hash(
        p_controller_session_id
      ),
      controller_disconnected_at=null,
      updated_at=now()
  where match_id=p_match_id
    and controller_profile_id is null
    and controller_session_id is null;

  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

create or replace function public.is_exact_live_controller(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language sql
stable
security definer
set search_path=public,extensions
as $$
  select exists(
    select 1
    from public.live_sessions ls
    join public.profiles p on p.id=auth.uid()
    where ls.match_id=p_match_id
      and ls.controller_profile_id=auth.uid()
      and ls.controller_session_id=public.live_session_token_hash(
        p_controller_session_id
      )
      and p.role in('admin','moderateur')
      and p.status='active'
  );
$$;

create or replace function public.release_live_control(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  affected integer;
begin
  update public.live_sessions
  set controller_profile_id=null,
      controller_session_id=null,
      controller_disconnected_at=null,
      updated_at=now()
  where match_id=p_match_id
    and controller_profile_id=auth.uid()
    and controller_session_id=public.live_session_token_hash(
      p_controller_session_id
    );

  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

create or replace function public.mark_live_disconnected(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  affected integer;
begin
  update public.live_sessions
  set controller_disconnected_at=now(),
      updated_at=now()
  where match_id=p_match_id
    and controller_profile_id=auth.uid()
    and controller_session_id=public.live_session_token_hash(
      p_controller_session_id
    );

  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

create or replace function public.force_resume_live(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  affected integer;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required';
  end if;
  if coalesce(length(p_controller_session_id),0)<32 then
    raise exception 'Invalid controller token';
  end if;

  update public.live_sessions
  set controller_profile_id=auth.uid(),
      controller_session_id=public.live_session_token_hash(
        p_controller_session_id
      ),
      controller_disconnected_at=null,
      updated_at=now()
  where match_id=p_match_id
    and controller_disconnected_at is not null
    and controller_disconnected_at<=now()-interval '60 seconds';

  get diagnostics affected=row_count;
  return affected=1;
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
set search_path=public,extensions
as $$
declare
  affected integer;
  live_id uuid;
begin
  if p_status not in(
    'not_started','running','paused','halftime','finished'
  ) then
    raise exception 'Invalid live status';
  end if;
  if not public.is_exact_live_controller(
    p_match_id,p_controller_session_id
  ) then
    return false;
  end if;

  select id into live_id
  from public.live_sessions
  where match_id=p_match_id;

  if p_status='running' and not exists(
    select 1
    from public.match_player_intervals
    where match_id=p_match_id
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
          then elapsed_seconds+greatest(
            0,
            floor(extract(epoch from(now()-clock_started_at)))::integer
          )
        else elapsed_seconds
      end,
      status=p_status,
      clock_started_at=case
        when p_status='running' then now()
        else null
      end,
      updated_at=now()
  where match_id=p_match_id
    and controller_profile_id=auth.uid()
    and controller_session_id=public.live_session_token_hash(
      p_controller_session_id
    );

  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

update public.live_sessions
set controller_profile_id=null,
    controller_session_id=null,
    controller_disconnected_at=null
where controller_session_id is not null;
