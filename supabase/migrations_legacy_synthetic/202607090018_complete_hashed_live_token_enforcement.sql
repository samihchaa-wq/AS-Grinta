create or replace function public.move_live_player(
  p_match_id uuid,
  p_controller_session_id text,
  p_profile_id uuid,
  p_slot_code text
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  sid uuid;
begin
  if not public.is_exact_live_controller(
    p_match_id,p_controller_session_id
  ) then
    return false;
  end if;

  select id into sid
  from public.live_sessions
  where match_id=p_match_id;

  if not exists(
    select 1
    from public.match_participants
    where match_id=p_match_id
      and profile_id=p_profile_id
  ) then
    raise exception 'Player is not a match participant';
  end if;

  delete from public.live_positions
  where live_session_id=sid
    and (
      profile_id=p_profile_id
      or (p_slot_code is not null and slot_code=p_slot_code)
    );

  if p_slot_code is not null and p_slot_code<>'bench' then
    insert into public.live_positions(
      live_session_id,profile_id,slot_code
    ) values(sid,p_profile_id,p_slot_code);
  end if;

  return true;
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
set search_path=public,extensions
as $$
begin
  if not public.is_exact_live_controller(
    p_match_id,p_controller_session_id
  ) then
    return false;
  end if;

  if not exists(
    select 1 from public.formations where code=p_formation
  ) then
    raise exception 'Unknown formation';
  end if;

  update public.live_sessions
  set formation=p_formation,
      updated_at=now()
  where match_id=p_match_id
    and controller_profile_id=auth.uid()
    and controller_session_id=public.live_session_token_hash(
      p_controller_session_id
    );

  return found;
end;
$$;
