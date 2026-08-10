drop policy if exists live_sessions_controller_update on public.live_sessions;
create policy live_sessions_controller_update on public.live_sessions
for update to authenticated
using (
  public.is_moderator()
  or (
    public.is_admin()
    and (
      controller_profile_id = auth.uid()
      or (controller_profile_id is null and controller_session_id is null)
    )
  )
)
with check (
  public.is_moderator()
  or (public.is_admin() and controller_profile_id = auth.uid())
);

create or replace function public.guard_live_session_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    if old.status = 'running' and old.clock_started_at is not null then
      new.elapsed_seconds := old.elapsed_seconds
        + greatest(0, floor(extract(epoch from (now() - old.clock_started_at)))::integer);
    else
      new.elapsed_seconds := old.elapsed_seconds;
    end if;
    new.clock_started_at := case when new.status = 'running' then now() else null end;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_guard_live_session_update on public.live_sessions;
create trigger trg_guard_live_session_update
before update on public.live_sessions
for each row execute function public.guard_live_session_update();

create or replace function public.apply_substitution_to_positions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  out_player uuid;
  out_slot text;
begin
  if new.action <> 'in' then return new; end if;

  select s.profile_id into out_player
  from public.substitutions s
  where s.live_session_id = new.live_session_id
    and s.minute = new.minute
    and s.action = 'out'
    and s.created_at <= new.created_at
  order by s.created_at desc, s.id desc
  limit 1;

  if out_player is null then return new; end if;

  select slot_code into out_slot
  from public.live_positions
  where live_session_id = new.live_session_id
    and profile_id = out_player;

  if out_slot is null then return new; end if;

  delete from public.live_positions
  where live_session_id = new.live_session_id
    and profile_id in (out_player, new.profile_id);

  insert into public.live_positions(live_session_id, profile_id, slot_code)
  values (new.live_session_id, new.profile_id, out_slot);

  return new;
end;
$$;

drop trigger if exists trg_apply_substitution_to_positions on public.substitutions;
create trigger trg_apply_substitution_to_positions
after insert on public.substitutions
for each row execute function public.apply_substitution_to_positions();

create or replace function public.create_live_session_if_missing(p_match_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid;
begin
  if not public.is_admin() then raise exception 'Admin role required'; end if;

  insert into public.live_sessions(match_id, status, elapsed_seconds)
  values (p_match_id, 'not_started', 0)
  on conflict (match_id) do nothing;

  select id into sid from public.live_sessions where match_id = p_match_id;
  return sid;
end;
$$;

grant execute on function public.create_live_session_if_missing(uuid) to authenticated;

create or replace function public.archive_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin role required'; end if;

  update public.matches
  set status = 'archive', updated_at = now()
  where id = p_match_id and status <> 'archive';

  return found;
end;
$$;

grant execute on function public.archive_match(uuid) to authenticated;
