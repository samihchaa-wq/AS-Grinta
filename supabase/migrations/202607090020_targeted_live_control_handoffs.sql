create table if not exists public.live_control_handoffs(
  match_id uuid primary key references public.matches(id) on delete cascade,
  from_profile_id uuid not null references public.profiles(id) on delete cascade,
  to_profile_id uuid not null references public.profiles(id) on delete cascade,
  expires_at timestamptz not null default (now()+interval '5 minutes'),
  created_at timestamptz not null default now(),
  check(from_profile_id<>to_profile_id)
);

alter table public.live_control_handoffs enable row level security;
revoke insert,update,delete on public.live_control_handoffs from authenticated;

drop policy if exists live_control_handoffs_involved_read
on public.live_control_handoffs;
create policy live_control_handoffs_involved_read
on public.live_control_handoffs for select to authenticated
using(
  from_profile_id=(select auth.uid())
  or to_profile_id=(select auth.uid())
  or public.is_moderator()
);

create index if not exists idx_live_control_handoffs_to_profile
on public.live_control_handoffs(to_profile_id,expires_at);

create or replace function public.offer_live_control(
  p_match_id uuid,
  p_controller_session_id text,
  p_target_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin role required';
  end if;
  if not public.is_exact_live_controller(
    p_match_id,p_controller_session_id
  ) then
    return false;
  end if;
  if p_target_profile_id=auth.uid() then
    raise exception 'Target must be another Admin';
  end if;
  if not exists(
    select 1 from public.profiles
    where id=p_target_profile_id
      and role='admin'
      and status='active'
  ) then
    raise exception 'Target Admin is unavailable';
  end if;

  insert into public.live_control_handoffs(
    match_id,from_profile_id,to_profile_id,expires_at,created_at
  ) values(
    p_match_id,auth.uid(),p_target_profile_id,now()+interval '5 minutes',now()
  )
  on conflict(match_id) do update
  set from_profile_id=excluded.from_profile_id,
      to_profile_id=excluded.to_profile_id,
      expires_at=excluded.expires_at,
      created_at=excluded.created_at;
  return true;
end;
$$;

create or replace function public.accept_live_control(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  offer_record public.live_control_handoffs%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Admin role required';
  end if;
  if coalesce(length(p_controller_session_id),0)<32 then
    raise exception 'Invalid controller token';
  end if;

  select * into offer_record
  from public.live_control_handoffs
  where match_id=p_match_id
    and to_profile_id=auth.uid()
    and expires_at>now()
  for update;

  if not found then return false; end if;

  update public.live_sessions
  set controller_profile_id=auth.uid(),
      controller_session_id=public.live_session_token_hash(
        p_controller_session_id
      ),
      controller_disconnected_at=null,
      updated_at=now()
  where match_id=p_match_id
    and controller_profile_id=offer_record.from_profile_id;

  if not found then return false; end if;

  delete from public.live_control_handoffs where match_id=p_match_id;
  return true;
end;
$$;

create or replace function public.cancel_live_control_offer(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
begin
  if not public.is_exact_live_controller(
    p_match_id,p_controller_session_id
  ) then
    return false;
  end if;
  delete from public.live_control_handoffs
  where match_id=p_match_id
    and from_profile_id=auth.uid();
  return true;
end;
$$;

revoke execute on function public.offer_live_control(uuid,text,uuid)
from public;
revoke execute on function public.offer_live_control(uuid,text,uuid)
from anon;
grant execute on function public.offer_live_control(uuid,text,uuid)
to authenticated;

revoke execute on function public.accept_live_control(uuid,text)
from public;
revoke execute on function public.accept_live_control(uuid,text)
from anon;
grant execute on function public.accept_live_control(uuid,text)
to authenticated;

revoke execute on function public.cancel_live_control_offer(uuid,text)
from public;
revoke execute on function public.cancel_live_control_offer(uuid,text)
from anon;
grant execute on function public.cancel_live_control_offer(uuid,text)
to authenticated;
